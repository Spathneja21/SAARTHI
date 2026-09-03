"""Guards that CP-SAT never schedules on top of a fixed class.

The bug this catches: saarthi/fixed_tasks.json was read only by dashboard.py,
so the solver had no idea the timetable existed and happily booked tasks
inside a lab session (e.g. "check emails" 14:22-14:37 landed inside
URA402 ISD LAB, 13:50-15:30, on Fri 2026-08-21).

Fixed events used to come from `cpsat_bridge.timetable_events(start, end)`, which
read that JSON file. Blocked time is now per-user and lives in the
`fixed_commitments` table, so that function needs a database session. The
invariant under test here belongs to the *packer*, not to the data source, so the
events are built locally from the same JSON fixture — keeping this a fast, pure
test instead of an integration test that needs Postgres and a seeded user.
"""
import json
import os
from datetime import datetime, time, timedelta

from core.tz import IST
from saarthi.Models import Chunk, FixedEvent
from saarthi.calendar_ import compute_free_windows
from saarthi.config import DEFAULT_CONFIG
from saarthi.packer import pack

TIMETABLE_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "saarthi", "fixed_tasks.json"
)


def events_from_fixture(start: datetime, end: datetime) -> list[FixedEvent]:
    """Project the JSON timetable onto concrete dates in [start, end].

    Mirrors what cpsat_bridge.timetable_events did before commitments moved into
    the database, so this test still exercises a realistic, densely-booked week.
    """
    with open(TIMETABLE_PATH) as f:
        entries = json.load(f)

    events: list[FixedEvent] = []
    day = start.date()
    while day <= end.date():
        weekday = day.strftime("%A")
        for e in entries:
            if e["Day"] != weekday:
                continue
            s = datetime.combine(day, time.fromisoformat(e["Start"]), tzinfo=IST)
            en = datetime.combine(day, time.fromisoformat(e["End"]), tzinfo=IST)
            if en > start:
                events.append(FixedEvent(
                    id=f"class_{day}_{e['Start']}", title=e["Task"],
                    start=s, end=en,
                ))
        day += timedelta(days=1)
    return events


def test_no_chunk_overlaps_a_class():
    start = datetime(2026, 8, 21, 8, 0, tzinfo=IST)   # Friday, before classes
    horizon_end = start + timedelta(days=DEFAULT_CONFIG.horizon_days)

    classes = events_from_fixture(start, horizon_end)
    assert classes, "expected the timetable to yield fixed events"

    # Enough chunks to force the solver into contested daytime hours.
    chunks = [
        Chunk(
            id=f"c{i}", parent_id=f"t{i}", parent_name=f"task {i}", index=0,
            duration=timedelta(minutes=45), deadline=horizon_end,
            is_final=True, break_after=timedelta(0),
        )
        for i in range(12)
    ]

    windows = compute_free_windows(classes, start, horizon_end, DEFAULT_CONFIG)
    plan = pack(chunks, windows, start, horizon_end, config=DEFAULT_CONFIG)
    assert plan.assignments, "expected chunks to be scheduled"

    for a in plan.assignments:
        for c in classes:
            overlap = a.start < c.end and c.start < a.end
            assert not overlap, (
                f"{a.chunk_id} {a.start:%a %H:%M}-{a.end:%H:%M} overlaps "
                f"{c.title} {c.start:%a %H:%M}-{c.end:%H:%M}"
            )


if __name__ == "__main__":
    test_no_chunk_overlaps_a_class()
    print("ok")
