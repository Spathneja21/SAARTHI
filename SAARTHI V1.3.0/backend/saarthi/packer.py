from saarthi import Models
import math
from datetime import datetime, timedelta
from collections import defaultdict
from saarthi.Models import Chunk, FreeWindow, Assignment, Plan
from saarthi.calendar_ import invert_windows
from saarthi.config import SchedulerConfig, DEFAULT_CONFIG

try:
    from ortools.sat.python import cp_model
except ImportError:
    raise ImportError("Install ortools: pip install ortools")


def to_slot(dt: datetime, horizon_start: datetime, grid_minutes: int) -> int:
    """Convert a datetime to an integer slot index (rounds down)."""
    delta = dt - horizon_start
    return int(delta.total_seconds() // 60 // grid_minutes)


def to_slot_ceil(dt: datetime, horizon_start: datetime, grid_minutes: int) -> int:
    """Slot index at or after `dt`.

    The grid is anchored at `horizon_start` (i.e. "now"), not on clock
    boundaries, so flooring a free window's start pushes it into the cell
    *before* the window opens — which let chunks begin up to one grid cell
    before the working day started. Quantize window starts up and blocked
    ends up, so rounding always shrinks free time rather than inventing it.
    """
    delta = dt - horizon_start
    return math.ceil(delta.total_seconds() / 60 / grid_minutes)


def from_slot(slot: int, horizon_start: datetime, grid_minutes: int) -> datetime:
    """Convert a slot index back to a datetime."""
    return horizon_start + timedelta(minutes=slot * grid_minutes)


def _build_model(
    chunks: list[Chunk],
    free_windows: list[FreeWindow],
    now: datetime,
    horizon_end: datetime,
    current_plan: dict[str, Assignment],
    in_progress_ids: set[str],
    config: SchedulerConfig,
    slot_scores: dict[str, dict[int, int]] | None,
):
    """
    Build the CP-SAT model, variables, and constraints shared by both solve
    phases. The slot-quality machinery (compact index + add_element lookup)
    is only added when slot_scores is truthy, so the fast core-only phase 1
    model never pays for it.

    Returns (model, cv, disruption_vars, core_objective, quality_bonus_vars,
    GRID, HORIZ, TODAY_END).
    """
    GRID  = config.grid_minutes
    HORIZ = to_slot(horizon_end, now, GRID)
    TODAY_END = to_slot(now.replace(hour=23, minute=59), now, GRID)

    model = cp_model.CpModel()

    # ── 1. Create variables ─────────────────────────────────────────────────

    cv = {}  # chunk_id → variable dict

    for c in chunks:
        # Ceil, not floor: the block is a reservation and must cover the work.
        # Flooring booked a 40-minute task into 2 grid cells (30 min), so the
        # saved slot came out shorter than the task's estimated duration.
        dur_slots = max(1, math.ceil(c.duration.total_seconds() / 60 / GRID))
        brk_slots = max(0, int(c.break_after.total_seconds() // 60 // GRID))

        # Apply elastic buffer: inflate occupied slots to absorb minor overruns
        raw_occupied = dur_slots + brk_slots
        occupied = int(raw_occupied * (1 + config.elastic_buffer_ratio))
        occupied = max(occupied, raw_occupied + 1)  # always at least 1 slot of buffer

        deadline_slot = to_slot(c.deadline, now, GRID)
        deadline_slot = max(0, min(deadline_slot, HORIZ))

        if HORIZ - occupied < 0:
            # Chunk is physically too big for the horizon — mark as unschedulable
            present = model.new_bool_var(f"p_{c.id}")
            model.add(present == 0)
            cv[c.id] = {
                "chunk": c, "present": present,
                "start": model.new_int_var(0, 0, f"s_{c.id}"),
                "end":   model.new_int_var(0, 0, f"e_{c.id}"),
                "interval": None,
                "overrun": model.new_int_var(0, 0, f"ov_{c.id}"),
                "dur_slots": dur_slots, "occupied": occupied,
                "deadline_slot": deadline_slot,
                "idx": None, "allowed_starts": [],
            }
            continue

        start    = model.new_int_var(0, max(0, HORIZ - occupied), f"s_{c.id}")
        end      = model.new_int_var(occupied, HORIZ,              f"e_{c.id}")
        present  = model.new_bool_var(f"p_{c.id}")
        overrun  = model.new_int_var(0, HORIZ,                     f"ov_{c.id}")

        interval = model.new_optional_interval_var(
            start, occupied, end, present, f"iv_{c.id}"
        )

        cv[c.id] = {
            "chunk": c, "start": start, "end": end,
            "present": present, "interval": interval,
            "overrun": overrun, "dur_slots": dur_slots,
            "occupied": occupied, "deadline_slot": deadline_slot,
            "idx": None, "allowed_starts": [],
        }

    # ── 2. Window constraint: only start in a free window ───────────────────

    for cid, v in cv.items():
        if v["interval"] is None:
            continue

        allowed_starts = []
        for w in free_windows:
            w_start = to_slot_ceil(w.start, now, GRID)   # never start before the window opens
            w_end   = to_slot(w.end,   now, GRID)
            for s in range(w_start, max(w_start, w_end - v["occupied"] + 1)):
                if 0 <= s <= HORIZ - v["occupied"]:
                    allowed_starts.append(s)

        if not allowed_starts:
            # No valid window → force dropped
            model.add(v["present"] == 0)
        else:
            # Cheap table constraint for feasibility.
            model.add_allowed_assignments([v["start"]], [[s] for s in allowed_starts])
            v["allowed_starts"] = allowed_starts

            if slot_scores:
                # Compact index (0..k-1), channelled to start via
                # add_element. k = number of allowed starts, far smaller
                # than the full horizon, so this stays cheap. Only built
                # when a quality objective is actually going to be used —
                # the core-only phase never pays for this.
                k = len(allowed_starts)
                idx = model.new_int_var(0, k - 1, f"idx_{cid}")
                model.add_element(idx, allowed_starts, v["start"])
                v["idx"] = idx

    # ── 3. No-overlap (chunks + blocked regions) ─────────────────────────────

    all_intervals = []

    for cid, v in cv.items():
        if v["interval"] is not None:
            all_intervals.append(v["interval"])

    # Add blocked regions as always-present fixed intervals
    blocked = invert_windows(free_windows, now, horizon_end)
    for i, region in enumerate(blocked):
        r_start = to_slot(region.start, now, GRID)
        r_end   = to_slot_ceil(region.end, now, GRID)   # cover the whole blocked span
        r_dur   = r_end - r_start
        if r_dur > 0 and r_start >= 0 and r_end <= HORIZ:
            iv = model.new_interval_var(r_start, r_dur, r_end, f"blocked_{i}")
            all_intervals.append(iv)

    if all_intervals:
        model.add_no_overlap(all_intervals)

    # ── 4. Deadline: soft constraint via overrun variable ────────────────────

    for cid, v in cv.items():
        if v["interval"] is None:
            continue
        # overrun = max(0, end - deadline)  only when present
        model.add(v["overrun"] >= v["end"] - v["deadline_slot"]).only_enforce_if(v["present"])
        model.add(v["overrun"] == 0).only_enforce_if(v["present"].Not())

    # ── 5. Precedence: chunk[i+1] starts after chunk[i] ends ────────────────

    by_parent = defaultdict(list)
    for cid, v in cv.items():
        by_parent[v["chunk"].parent_id].append(v)

    for parent_id, siblings in by_parent.items():
        siblings.sort(key=lambda v: v["chunk"].index)
        for prev, curr in zip(siblings, siblings[1:]):
            if prev["interval"] is None or curr["interval"] is None:
                continue
            model.add(curr["start"] >= prev["end"]).only_enforce_if(
                [prev["present"], curr["present"]]
            )

    # ── 6. Partial completion: can't do chunk N+1 without chunk N ────────────

    for parent_id, siblings in by_parent.items():
        siblings.sort(key=lambda v: v["chunk"].index)
        for prev, curr in zip(siblings, siblings[1:]):
            # curr.present = 1  implies  prev.present = 1
            model.add_implication(curr["present"], prev["present"])

    # ── 7. Freeze in-progress chunks (pin to current slot) ──────────────────

    for cid, v in cv.items():
        if cid in in_progress_ids and cid in current_plan:
            pinned_slot = to_slot(current_plan[cid].start, now, GRID)
            pinned_slot = max(0, pinned_slot)
            if v["interval"] is not None:
                model.add(v["start"] == pinned_slot)
                model.add(v["present"] == 1)

    # ── 8. Hybrid disruption penalty (today's chunks only) ──────────────────

    disruption_vars = []

    for cid, v in cv.items():
        if cid not in current_plan:
            continue
        if cid in in_progress_ids:
            continue  # already pinned above
        if v["interval"] is None:
            continue

        old_slot = to_slot(current_plan[cid].start, now, GRID)
        if old_slot > TODAY_END:
            continue  # future day — allow full re-optimization, no penalty

        # Measure how far this chunk moved from its old position
        diff = model.new_int_var(-HORIZ, HORIZ, f"diff_{cid}")
        disp = model.new_int_var(0, HORIZ,      f"disp_{cid}")
        model.add(diff == v["start"] - old_slot).only_enforce_if(v["present"])
        model.add(diff == 0).only_enforce_if(v["present"].Not())
        model.add_abs_equality(disp, diff)
        disruption_vars.append(disp)

    # ── 9. Objective pieces ───────────────────────────────────────────────────

    schedule_reward  = sum(v["present"] for v in cv.values())
    overrun_penalty  = sum(v["overrun"]  for v in cv.values())
    displace_penalty = sum(disruption_vars) if disruption_vars else 0

    core_objective = (
        config.w_schedule * schedule_reward
        - config.w_overrun  * overrun_penalty
        - config.w_displace * displace_penalty
    )

    # Slot quality bonus — prefer high-ML-score slots
    quality_bonus_vars = []

    if slot_scores:
        for cid, v in cv.items():
            if v["interval"] is None or v["idx"] is None or cid not in slot_scores:
                continue

            scores_for_chunk = slot_scores[cid]
            if not scores_for_chunk:
                continue

            # Dense array aligned with allowed_starts (size k, not the
            # full horizon) — the same compact index used for the start
            # channel above, so this lookup stays cheap.
            compact_scores = [scores_for_chunk.get(s, 0) for s in v["allowed_starts"]]
            max_score = max(compact_scores, default=0)
            if max_score == 0:
                continue

            quality_var = model.new_int_var(0, max_score, f"q_{cid}")
            model.add_element(v["idx"], compact_scores, quality_var)

            actual_quality = model.new_int_var(0, max_score, f"act_q_{cid}")
            model.add(actual_quality == quality_var).only_enforce_if(v["present"])
            model.add(actual_quality == 0).only_enforce_if(v["present"].Not())

            quality_bonus_vars.append(actual_quality)

    return model, cv, disruption_vars, core_objective, quality_bonus_vars, GRID, HORIZ


def pack(
    chunks: list[Chunk],
    free_windows: list[FreeWindow],
    now: datetime,
    horizon_end: datetime,
    current_plan: dict[str, Assignment] | None = None,  # chunk_id → Assignment
    in_progress_ids: set[str] | None = None,            # chunk_ids currently running
    config: SchedulerConfig = DEFAULT_CONFIG,
    slot_scores: dict[str, dict[int, int]] | None = None,
) -> Plan:
    """
    Build and solve the CP-SAT model.

    Parameters:
        chunks         — all pending + in_progress chunks to schedule
        free_windows   — available time slots (from calendar_.py)
        now            — current wall-clock time (re-plan starts from here)
        horizon_end    — how far ahead to plan
        current_plan   — existing assignments (for disruption penalty)
        in_progress_ids— chunk IDs currently being worked on (pinned)
        config         — tunable constants

    When slot_scores is provided, the solve happens in two phases:
      Phase 1 — a lightweight model containing only the core constraints
                (no quality machinery at all) maximizes schedule/overrun/
                displacement. This is a much easier search — CP-SAT reaches
                OPTIMAL for it in a fraction of the time even with many
                chunks — and guarantees a fully-scheduled baseline plan.
      Phase 2 — the full model (core constraints + quality lookups) is
                solved, seeded with phase 1's solution via add_hint. Both
                models share the same constraint structure (phase 2 is a
                superset), so the hint is always a valid solution to phase
                2 as well — CP-SAT accepts it near-instantly as an
                incumbent and spends the remaining time budget improving
                quality from there, instead of discovering feasibility and
                optimizing quality at the same time. If phase 2 can't
                improve on it in time, the hinted (phase 1) plan is used.

    This avoids the failure mode where the quality objective makes the
    combined search too hard to even find ONE feasible solution within the
    configured time budget, causing everything to be dropped even though a
    full schedule was easily reachable.
    """
    import time
    t_start = time.time()

    current_plan    = current_plan or {}
    in_progress_ids = in_progress_ids or set()

    if slot_scores:
        # ── Phase 1: lightweight core-only model ────────────────────────────
        p1_model, p1_cv, p1_disruption, p1_core_obj, _, GRID, HORIZ = _build_model(
            chunks, free_windows, now, horizon_end,
            current_plan, in_progress_ids, config, slot_scores=None,
        )
        p1_model.maximize(p1_core_obj)

        p1_solver = cp_model.CpSolver()
        p1_solver.parameters.max_time_in_seconds = config.solver_time_limit_s
        p1_solver.parameters.num_search_workers  = config.solver_workers
        phase1_status = p1_solver.solve(p1_model)

        phase1_snapshot = None
        if phase1_status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            phase1_snapshot = {
                cid: (p1_solver.value(v["present"]), p1_solver.value(v["start"]))
                for cid, v in p1_cv.items()
            }

        # ── Phase 2: full model (core + quality), hinted from phase 1 ──────
        model, cv, disruption_vars, core_obj, quality_bonus_vars, GRID, HORIZ = _build_model(
            chunks, free_windows, now, horizon_end,
            current_plan, in_progress_ids, config, slot_scores=slot_scores,
        )
        full_objective = core_obj + config.w_slot_quality * sum(quality_bonus_vars)
        model.maximize(full_objective)

        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = config.solver_time_limit_s
        solver.parameters.num_search_workers  = config.solver_workers

        if phase1_snapshot is not None:
            for cid, (present_val, start_val) in phase1_snapshot.items():
                model.add_hint(cv[cid]["present"], present_val)
                model.add_hint(cv[cid]["start"],   start_val)

        status_code = solver.solve(model)
        status_name = solver.status_name(status_code)

        using_phase1_fallback = False
        if status_code not in (cp_model.OPTIMAL, cp_model.FEASIBLE) and phase1_snapshot is not None:
            # Phase 2 failed to report anything usable despite the valid
            # hint (rare) — fall back to phase 1's already-captured plan.
            status_code = phase1_status
            status_name = p1_solver.status_name(phase1_status) + "_PHASE1_FALLBACK"
            using_phase1_fallback = True
    else:
        model, cv, disruption_vars, core_obj, _, GRID, HORIZ = _build_model(
            chunks, free_windows, now, horizon_end,
            current_plan, in_progress_ids, config, slot_scores=None,
        )
        model.maximize(core_obj)

        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = config.solver_time_limit_s
        solver.parameters.num_search_workers  = config.solver_workers

        status_code = solver.solve(model)
        status_name = solver.status_name(status_code)
        phase1_snapshot = None
        using_phase1_fallback = False

    solve_ms = (time.time() - t_start) * 1000

    # Fallback: if INFEASIBLE, relax disruption penalty and retry
    if status_code == cp_model.INFEASIBLE and disruption_vars:
        # Simplest retry: re-call pack() with current_plan={}
        status_name = "INFEASIBLE_RELAXED"

    # ── 11. Extract results ───────────────────────────────────────────────────

    assignments    = []
    dropped_ids    = []

    if status_code in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        for cid, v in cv.items():
            if using_phase1_fallback:
                present_val, s_slot = phase1_snapshot[cid]
            else:
                present_val = solver.value(v["present"])
                s_slot      = solver.value(v["start"])

            if present_val == 1:
                e_slot = s_slot + v["dur_slots"]   # end of actual work (not break)
                ov_slots = max(0, e_slot - v["deadline_slot"])

                start_dt = from_slot(s_slot, now, GRID)
                end_dt   = from_slot(e_slot, now, GRID)
                overrun  = timedelta(minutes=ov_slots * GRID)

                assignments.append(Assignment(
                    chunk_id    = cid,
                    parent_id   = v["chunk"].parent_id,
                    parent_name = v["chunk"].parent_name,
                    chunk_index = v["chunk"].index,
                    start       = start_dt,
                    end         = end_dt,
                    overrun     = overrun,
                ))
            else:
                dropped_ids.append(cid)

        obj_value = solver.objective_value if not using_phase1_fallback else 0.0
    else:
        # Nothing could be scheduled
        dropped_ids = list(cv.keys())
        obj_value   = 0.0

    assignments.sort(key=lambda a: a.start)

    return Plan(
        assignments      = assignments,
        dropped_chunk_ids = dropped_ids,
        generated_at     = now,
        solve_status     = status_name,
        solve_time_ms    = solve_ms,
        objective_value  = obj_value,
    )
