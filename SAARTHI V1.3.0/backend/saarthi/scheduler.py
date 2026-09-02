from dataclasses import replace
from datetime import datetime, timedelta
from core.tz import now as ist_now
from saarthi.Models import Task, Chunk, FreeWindow, Assignment, Plan, ChunkStatus
from saarthi.calendar_ import compute_free_windows
from saarthi.chunker import chunk_task
from saarthi.packer import pack
from saarthi.degradation import classify, TaskStatus
from saarthi.config import SchedulerConfig, DEFAULT_CONFIG


class Scheduler:
    def __init__(self, config: SchedulerConfig = DEFAULT_CONFIG):
        self.config        = config
        self.tasks:  dict[str, Task]       = {}
        self.chunks: dict[str, Chunk]      = {}  # chunk_id → Chunk
        self.plan:   Plan | None           = None
        self.fixed_events                  = []
        self.free_windows: list[FreeWindow] = []
        self._horizon_end: datetime | None = None
        self.slot_scores: dict[str, dict[int, int]] | None = None

    # ── Calendar ────────────────────────────────────────────────────────────

    def set_calendar(self, fixed_events: list, now: datetime | None = None):
        """Call whenever the user's calendar changes."""
        self.fixed_events = fixed_events
        now = now or ist_now()
        self._horizon_end = now + timedelta(days=self.config.horizon_days)
        self.free_windows = compute_free_windows(
            fixed_events, now, self._horizon_end, self.config
        )
        self._replan(now)

    # ── Task management ──────────────────────────────────────────────────────

    def add_task(self, task: Task, now: datetime | None = None, replan: bool = True):
        """Add a new task. Re-plans automatically unless replan=False."""
        now = now or ist_now()
        self.tasks[task.id] = task

        new_chunks = chunk_task(task, self.config)
        for c in new_chunks:
            self.chunks[c.id] = c

        if replan:
            self._replan(now)

    def complete_chunk(self, chunk_id: str, now: datetime | None = None):
        """Mark a chunk done (possibly early). Triggers re-plan."""
        now = now or ist_now()
        if chunk_id in self.chunks:
            c = self.chunks[chunk_id]
            self.chunks[chunk_id] = replace(c, status=ChunkStatus.DONE)
        self._replan(now)

    def skip_chunk(self, chunk_id: str, now: datetime | None = None):
        """User explicitly skips a chunk. Triggers re-plan."""
        now = now or ist_now()
        if chunk_id in self.chunks:
            c = self.chunks[chunk_id]
            self.chunks[chunk_id] = replace(c, status=ChunkStatus.SKIPPED)
        self._replan(now)

    def mark_in_progress(self, chunk_id: str, now: datetime | None = None):
        """Mark a chunk as currently being worked on (freezes it in re-plans)."""
        now = now or ist_now()
        if chunk_id in self.chunks:
            c = self.chunks[chunk_id]
            self.chunks[chunk_id] = replace(c, status=ChunkStatus.IN_PROGRESS)

    # ── Core re-plan ─────────────────────────────────────────────────────────

    def _replan(self, now: datetime):
        if not self.free_windows:
            return

        horizon_end = now + timedelta(days=self.config.horizon_days)

        # Only pass pending and in-progress chunks to the solver
        active_chunks = [
            c for c in self.chunks.values()
            if c.status in (ChunkStatus.PENDING, ChunkStatus.IN_PROGRESS)
        ]

        if not active_chunks:
            self.plan = None
            return

        # Build current_plan dict from existing assignments
        current_plan: dict[str, Assignment] = {}
        if self.plan:
            for a in self.plan.assignments:
                current_plan[a.chunk_id] = a

        in_progress_ids = {
            c.id for c in active_chunks if c.status == ChunkStatus.IN_PROGRESS
        }

        self.plan = pack(
            chunks          = active_chunks,
            free_windows    = self.free_windows,
            now             = now,
            horizon_end     = horizon_end,
            current_plan    = current_plan,
            in_progress_ids = in_progress_ids,
            config          = self.config,
            slot_scores     = getattr(self, 'slot_scores', None),
        )

    # ── Query ────────────────────────────────────────────────────────────────

    def get_plan(self) -> Plan | None:
        return self.plan

    def get_warnings(self) -> list[str]:
        if not self.plan:
            return []
        all_chunks = list(self.chunks.values())
        statuses = classify(self.plan, all_chunks)
        return [w for s in statuses if (w := s.warning()) is not None]

    def print_schedule(self, now: datetime | None = None):
        """Pretty-print the current schedule to stdout."""
        now = now or ist_now()
        if not self.plan:
            print("No plan generated.")
            return

        print(f"\n{'='*60}")
        print(f"  Schedule  |  Status: {self.plan.solve_status}"
              f"  |  Solved in {self.plan.solve_time_ms:.0f}ms")
        print(f"{'='*60}")

        for a in self.plan.assignments:
            flag = "⚠ LATE" if a.overrun.total_seconds() > 0 else "✓"
            print(f"  {flag}  {a.start.strftime('%a %d %b  %H:%M')} → "
                  f"{a.end.strftime('%H:%M')}  |  "
                  f"{a.parent_name} (chunk {a.chunk_index + 1})")

        if self.plan.dropped_chunk_ids:
            print(f"\n  Dropped: {len(self.plan.dropped_chunk_ids)} chunk(s)")

        warnings = self.get_warnings()
        if warnings:
            print(f"\n  Warnings:")
            for w in warnings:
                print(f"    → {w}")

        print(f"{'='*60}\n")
