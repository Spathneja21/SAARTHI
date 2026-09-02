import pandas as pd
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text


async def extract_features(db: AsyncSession) -> pd.DataFrame:
    query = text("""
        SELECT
            t.id,
            t.estimated_duration,
            t.priority,
            t.category::text,
            t.energy_requirement::text,
            t.procrastination_count,
            t.reschedule_count,
            t.skip_count,
            t.status::text,
            -- occurred_at is timestamptz and the DB session runs in UTC, so
            -- EXTRACT must be pinned to IST or training sees UTC hours while
            -- inference (main.py) sends IST hours.
            EXTRACT(HOUR FROM e.occurred_at AT TIME ZONE 'Asia/Kolkata') AS hour_of_day,
            EXTRACT(DOW  FROM e.occurred_at AT TIME ZONE 'Asia/Kolkata') AS day_of_week
        FROM tasks t
        JOIN task_events e
          ON e.task_id = t.id
         AND e.event_type = 'task_created'
        WHERE t.status::text IN ('completed', 'abandoned', 'skipped', 'partially_done')
    """)

    result = await db.execute(query)
    rows   = result.fetchall()

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows, columns=[
        "id", "estimated_duration", "priority", "category",
        "energy_requirement", "procrastination_count",
        "reschedule_count", "skip_count", "status",
        "hour_of_day", "day_of_week",
    ])

    # Label: 1 = completed, 0 = did not complete
    df["label"] = (df["status"] == "completed").astype(int)

    # Encode categoricals as numbers
    category_map = {
        "deep_work": 0, "admin": 1, "learning": 2,
        "meeting": 3, "personal": 4, "health": 5,
    }
    energy_map = {
        "very_low": 0, "low": 1, "medium": 2, "high": 3, "peak": 4,
    }
    df["category_enc"]         = df["category"].map(category_map).fillna(0)
    df["energy_requirement_enc"] = df["energy_requirement"].map(energy_map).fillna(2)

    return df