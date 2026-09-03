from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, model_validator

from models.models import (
    CommitmentRecurrence, EnergyLevel, TaskCategory, TaskStatus,
)


class RegisterRequest(BaseModel):
    email: EmailStr
    username: str
    password: str
    full_name: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserRead(BaseModel):
    id: UUID
    email: str
    username: str
    full_name: str | None
    timezone: str

    model_config = {"from_attributes": True}


# ── Tasks ──────────────────────────────────────────────────────────────────────

# `priority` is validated 1-10 to accommodate rows already in the database (the
# column default is 5), while the Flutter app sends 1-5. Note that priority feeds
# the ML feature vectors and is echoed in responses, but does NOT influence CP-SAT
# scheduling — the solver ranks slots by energy match, deadline urgency and the
# model's predictions, never by priority.
class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=500)
    category: TaskCategory
    energy_requirement: EnergyLevel
    estimated_duration: int = Field(gt=0, le=1440, description="Minutes.")
    priority: int = Field(default=5, ge=1, le=10)
    deadline: datetime | None = None
    description: str | None = None


# Every field optional: PATCH semantics, where an omitted field is left untouched.
# `None` is therefore ambiguous for nullable columns, so callers cannot clear a
# deadline through this route — an explicit endpoint would be needed for that.
class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    category: TaskCategory | None = None
    energy_requirement: EnergyLevel | None = None
    estimated_duration: int | None = Field(default=None, gt=0, le=1440)
    priority: int | None = Field(default=None, ge=1, le=10)
    deadline: datetime | None = None
    description: str | None = None


class TaskRead(BaseModel):
    id: UUID
    title: str
    description: str | None
    category: TaskCategory
    energy_requirement: EnergyLevel
    estimated_duration: int
    actual_duration: int | None
    priority: int
    deadline: datetime | None
    status: TaskStatus
    procrastination_count: int
    reschedule_count: int
    skip_count: int
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None
    completed_at: datetime | None

    model_config = {"from_attributes": True}


class TransitionRequest(BaseModel):
    to_status: TaskStatus
    reason: str | None = None


# ── Scheduling ─────────────────────────────────────────────────────────────────

class BookSlotRequest(BaseModel):
    task_id: UUID
    slot_start: datetime
    slot_end: datetime


class MoveSlotRequest(BaseModel):
    slot_id: UUID
    new_start: datetime
    new_end: datetime


class CpsatRequest(BaseModel):
    # Omit or send null to schedule every pending task the user has.
    task_ids: list[UUID] | None = None


# ── Nudge ──────────────────────────────────────────────────────────────────────

class NudgeRequest(BaseModel):
    heart_rate: int = Field(ge=0, le=250)
    hrv_ms: float = Field(ge=0)
    app_switches: int = Field(default=0, ge=0)
    screen_time_hours: float = Field(default=0.0, ge=0)
    minutes_since_break: int = Field(default=0, ge=0)


# ── Fixed commitments ──────────────────────────────────────────────────────────

# Times are minutes from midnight, matching the Flutter client's
# `ScheduleEntry.startMinutes`. 1440 is allowed as an end value so a commitment
# can run to midnight.
class FixedCommitmentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    recurrence: CommitmentRecurrence = CommitmentRecurrence.WEEKLY
    weekday: int | None = Field(default=None, ge=0, le=6,
                                description="0=Monday..6=Sunday. Weekly only.")
    specific_date: date | None = Field(default=None,
                                       description="One-time commitments only.")
    start_minute: int = Field(ge=0, le=1439)
    end_minute: int = Field(ge=1, le=1440)

    @model_validator(mode="after")
    def _check_shape(self) -> "FixedCommitmentCreate":
        if self.end_minute <= self.start_minute:
            raise ValueError("end_minute must be after start_minute")

        # Enforced here rather than in the database so the error names the field.
        # A weekly row without a weekday, or a one-time row without a date, would
        # silently match no day at all and block nothing.
        if self.recurrence == CommitmentRecurrence.WEEKLY and self.weekday is None:
            raise ValueError("weekday is required when recurrence is 'weekly'")
        if self.recurrence == CommitmentRecurrence.ONE_TIME and self.specific_date is None:
            raise ValueError("specific_date is required when recurrence is 'one_time'")
        return self


class FixedCommitmentRead(BaseModel):
    id: UUID
    title: str
    recurrence: CommitmentRecurrence
    weekday: int | None
    specific_date: date | None
    start_minute: int
    end_minute: int
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}