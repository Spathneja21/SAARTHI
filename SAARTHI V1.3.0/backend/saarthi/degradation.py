from dataclasses import dataclass
from datetime import timedelta
from saarthi.Models import Assignment, Chunk, Plan


@dataclass
class TaskStatus:
    parent_id: str
    parent_name: str
    total_chunks: int
    on_time: int
    overrun: int
    dropped: int

    @property
    def fully_scheduled(self) -> bool:
        return self.dropped == 0 and self.overrun == 0

    @property
    def partially_scheduled(self) -> bool:
        scheduled = self.on_time + self.overrun
        return self.dropped > 0 and scheduled > 0

    @property
    def completely_infeasible(self) -> bool:
        return self.on_time == 0 and self.overrun == 0

    @property
    def progress_ratio(self) -> float:
        return (self.on_time + self.overrun) / max(1, self.total_chunks)

    def warning(self) -> str | None:
        if self.fully_scheduled:
            return None
        if self.completely_infeasible:
            return f"'{self.parent_name}': could not schedule any part before deadline."
        if self.partially_scheduled:
            pct = int(self.progress_ratio * 100)
            return (f"'{self.parent_name}': only {pct}% fits before deadline "
                    f"({self.dropped} chunk(s) dropped).")
        if self.overrun > 0:
            return f"'{self.parent_name}': will finish past its deadline."
        return None


def classify(plan: Plan, all_chunks: list[Chunk]) -> list[TaskStatus]:
    """
    Summarise plan quality per parent task.
    Returns a list of TaskStatus, one per unique parent_id.
    """
    # Count totals per parent
    totals: dict[str, dict] = {}
    for c in all_chunks:
        if c.parent_id not in totals:
            totals[c.parent_id] = {
                "name": c.parent_name, "total": 0,
                "on_time": 0, "overrun": 0, "dropped": 0
            }
        totals[c.parent_id]["total"] += 1

    # Score assignments
    for a in plan.assignments:
        if a.overrun > timedelta(0):
            totals[a.parent_id]["overrun"] += 1
        else:
            totals[a.parent_id]["on_time"] += 1

    # Score dropped chunks
    assigned_ids = {a.chunk_id for a in plan.assignments}
    for c in all_chunks:
        if c.id in plan.dropped_chunk_ids or c.id not in assigned_ids:
            if c.id not in assigned_ids:
                totals[c.parent_id]["dropped"] += 1

    results = []
    for pid, d in totals.items():
        results.append(TaskStatus(
            parent_id=pid,
            parent_name=d["name"],
            total_chunks=d["total"],
            on_time=d["on_time"],
            overrun=d["overrun"],
            dropped=d["dropped"],
        ))

    return results
