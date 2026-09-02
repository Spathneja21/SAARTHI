from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Optional
import uuid


def new_id() -> str:
    return str(uuid.uuid4())[:8]


class ChunkStatus(str, Enum):
    PENDING     = "pending"
    IN_PROGRESS = "in_progress"
    DONE        = "done"
    SKIPPED     = "skipped"


@dataclass
class FixedEvent:
    """A calendar block that cannot be scheduled into."""
    id: str
    title: str
    start: datetime
    end: datetime


@dataclass
class FreeWindow:
    """A contiguous block of schedulable time."""
    start: datetime
    end: datetime

    @property
    def duration(self) -> timedelta:
        return self.end - self.start

    @property
    def duration_minutes(self) -> float:
        return self.duration.total_seconds() / 60


@dataclass
class Task:
    """A unit of work submitted by the user."""
    id: str
    name: str
    duration: timedelta          # estimated total time needed
    deadline: datetime           # must finish by this time
    focus_limit: timedelta       # max continuous focus before a break
    flexible: bool               # can be split into chunks?
    arrival_time: datetime = field(default_factory=datetime.now)

    @staticmethod
    def create(name: str, duration_minutes: int, deadline: datetime,
               focus_limit_minutes: int, flexible: bool) -> "Task":
        return Task(
            id=new_id(),
            name=name,
            duration=timedelta(minutes=duration_minutes),
            deadline=deadline,
            focus_limit=timedelta(minutes=focus_limit_minutes),
            flexible=flexible,
        )


@dataclass
class Chunk:
    """An atomic schedulable unit, derived from a Task."""
    id: str
    parent_id: str
    parent_name: str
    index: int                   # 0-based position within parent task
    duration: timedelta          # actual work time for this chunk
    deadline: datetime           # inherited from parent
    is_final: bool               # True = completing this chunk finishes the task
    break_after: timedelta       # mandatory rest after this chunk
    status: ChunkStatus = ChunkStatus.PENDING

    @property
    def occupied(self) -> timedelta:
        """Total time this chunk reserves (work + break)."""
        return self.duration + self.break_after


@dataclass
class Assignment:
    """A chunk placed at a specific time."""
    chunk_id: str
    parent_id: str
    parent_name: str
    chunk_index: int
    start: datetime
    end: datetime                # end of work (not including break)
    overrun: timedelta = field(default_factory=lambda: timedelta(0))

    @property
    def on_time(self) -> bool:
        return self.overrun == timedelta(0)


@dataclass
class Plan:
    """Output of the packer."""
    assignments: list[Assignment]
    dropped_chunk_ids: list[str]
    generated_at: datetime
    solve_status: str            # OPTIMAL / FEASIBLE / INFEASIBLE / UNKNOWN
    solve_time_ms: float
    objective_value: float
