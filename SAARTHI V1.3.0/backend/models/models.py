import uuid
from datetime import datetime, timezone
from core.tz import IST, now as ist_now
from sqlalchemy import String, Boolean, DateTime, Integer, Float, Text, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator
import enum


class ISTDateTime(TypeDecorator):
    """timestamptz that always reads back as IST.

    asyncpg decodes timestamptz to UTC-aware datetimes no matter what the
    session timezone is, so without this the write path emits +05:30 while
    the read path emits +00:00 — same instant, but every API response and
    .hour lookup downstream silently disagrees with the rest of the app.
    """
    impl = DateTime(timezone=True)
    cache_ok = True

    def process_result_value(self, value, dialect):
        return value.astimezone(IST) if value is not None else None


class Base(DeclarativeBase):
    pass


# ── Enums ──────────────────────────────────────────────────────────────────────

class TaskStatus(str, enum.Enum):
    DRAFT          = "draft"
    SCHEDULED      = "scheduled"
    IN_PROGRESS    = "in_progress"
    PAUSED         = "paused"
    COMPLETED      = "completed"
    PARTIALLY_DONE = "partially_done"
    POSTPONED      = "postponed"
    SKIPPED        = "skipped"
    ABANDONED      = "abandoned"


class TaskCategory(str, enum.Enum):
    DEEP_WORK = "deep_work"
    ADMIN     = "admin"
    LEARNING  = "learning"
    MEETING   = "meeting"
    PERSONAL  = "personal"
    HEALTH    = "health"


class EnergyLevel(str, enum.Enum):
    VERY_LOW = "very_low"
    LOW      = "low"
    MEDIUM   = "medium"
    HIGH     = "high"
    PEAK     = "peak"


# ── User ───────────────────────────────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(128), nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(200))
    timezone: Mapped[str] = mapped_column(String(50), default="Asia/Kolkata")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        ISTDateTime, default=lambda: ist_now()
    )


# ── Task ───────────────────────────────────────────────────────────────────────

class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    category: Mapped[TaskCategory] = mapped_column(
        SAEnum(TaskCategory), nullable=False, default=TaskCategory.DEEP_WORK
    )
    energy_requirement: Mapped[EnergyLevel] = mapped_column(
        SAEnum(EnergyLevel), nullable=False, default=EnergyLevel.MEDIUM
    )
    estimated_duration: Mapped[int] = mapped_column(Integer, nullable=False)  # minutes
    actual_duration: Mapped[int | None] = mapped_column(Integer)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    deadline: Mapped[datetime | None] = mapped_column(ISTDateTime)

    # State machine
    status: Mapped[TaskStatus] = mapped_column(
        SAEnum(TaskStatus), nullable=False, default=TaskStatus.DRAFT
    )
    procrastination_count: Mapped[int] = mapped_column(Integer, default=0)
    reschedule_count: Mapped[int] = mapped_column(Integer, default=0)
    skip_count: Mapped[int] = mapped_column(Integer, default=0)

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        ISTDateTime, default=lambda: ist_now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        ISTDateTime, default=lambda: ist_now()
    )
    started_at: Mapped[datetime | None] = mapped_column(ISTDateTime)
    completed_at: Mapped[datetime | None] = mapped_column(ISTDateTime)


class TaskEvent(Base):
    __tablename__ = "task_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    from_status: Mapped[str | None] = mapped_column(String(50))
    to_status: Mapped[str | None] = mapped_column(String(50))
    reason: Mapped[str | None] = mapped_column(Text)

    # ML signals — captured at the moment of the event
    hour_of_day: Mapped[int | None] = mapped_column(Integer)
    day_of_week: Mapped[int | None] = mapped_column(Integer)
    stress_score: Mapped[int | None] = mapped_column(Integer)

    occurred_at: Mapped[datetime] = mapped_column(
        ISTDateTime,
        default=lambda: ist_now(),
    )

class StressLog(Base):
    __tablename__ = "stress_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    heart_rate: Mapped[int] = mapped_column(Integer, nullable=False)
    hrv_ms: Mapped[float] = mapped_column(Float, nullable=False)
    app_switches: Mapped[int] = mapped_column(Integer, default=0)
    screen_time_hours: Mapped[float] = mapped_column(Float, default=0.0)
    minutes_since_break: Mapped[int] = mapped_column(Integer, default=0)

    # Computed
    stress_score: Mapped[int] = mapped_column(Integer, nullable=False)
    stress_level: Mapped[str] = mapped_column(String(20), nullable=False)
    nudge_type: Mapped[str] = mapped_column(String(30), nullable=False)

    hour_of_day: Mapped[int | None] = mapped_column(Integer)
    day_of_week: Mapped[int | None] = mapped_column(Integer)
    recorded_at: Mapped[datetime] = mapped_column(
        ISTDateTime,
        default=lambda: ist_now(),
    )


class UserBehaviorProfile(Base):
    __tablename__ = "user_behavior_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True
    )
    # Completion patterns
    total_tasks_created: Mapped[int] = mapped_column(Integer, default=0)
    total_tasks_completed: Mapped[int] = mapped_column(Integer, default=0)
    total_tasks_abandoned: Mapped[int] = mapped_column(Integer, default=0)
    completion_rate: Mapped[float] = mapped_column(Float, default=0.0)

    # Time accuracy
    avg_estimation_error_minutes: Mapped[float] = mapped_column(Float, default=0.0)
    # positive = underestimated, negative = overestimated

    # Procrastination signals
    avg_procrastination_count: Mapped[float] = mapped_column(Float, default=0.0)
    avg_reschedule_count: Mapped[float] = mapped_column(Float, default=0.0)
    avg_skip_count: Mapped[float] = mapped_column(Float, default=0.0)

    # Peak focus hours (learned from completions)
    peak_focus_hour_start: Mapped[int | None] = mapped_column(Integer)
    peak_focus_hour_end: Mapped[int | None] = mapped_column(Integer)

    # Most procrastinated category
    most_procrastinated_category: Mapped[str | None] = mapped_column(String(50))

    # Timestamps
    last_updated: Mapped[datetime] = mapped_column(
        ISTDateTime,
        default=lambda: ist_now(),
    )


class SlotPreferenceFeedback(Base):
    __tablename__ = "slot_preference_feedback"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    task_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)

    # What AURA suggested
    suggested_start   : Mapped[datetime] = mapped_column(ISTDateTime)
    suggested_score   : Mapped[float]    = mapped_column(Float)

    # What user chose (if they moved it)
    user_chosen_start : Mapped[datetime | None] = mapped_column(ISTDateTime)

    # Outcome
    was_completed     : Mapped[bool | None] = mapped_column(Boolean)
    was_kept          : Mapped[bool]        = mapped_column(Boolean, default=True)

    # RL reward signal
    reward            : Mapped[float | None] = mapped_column(Float)

    hour_of_day       : Mapped[int]          = mapped_column(Integer)
    day_of_week       : Mapped[int]          = mapped_column(Integer)
    created_at        : Mapped[datetime]     = mapped_column(ISTDateTime)

class ScheduledSlot(Base):
    __tablename__ = "scheduled_slots"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    scheduled_start: Mapped[datetime] = mapped_column(
        ISTDateTime, nullable=False
    )
    scheduled_end: Mapped[datetime] = mapped_column(
        ISTDateTime, nullable=False
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[str] = mapped_column(
        String(20), default="ai"
    )  # "ai" or "user"
    created_at: Mapped[datetime] = mapped_column(
        ISTDateTime,
        default=lambda: ist_now(),
    )