"""Guards that CP-SAT never schedules on top of a fixed class.

The bug this catches: saarthi/fixed_tasks.json was read only by dashboard.py,
so the solver had no idea the timetable existed and happily booked tasks
inside a lab session (e.g. "check emails" 14:22-14:37 landed inside
URA402 ISD LAB, 13:50-15:30, on Fri 2026-08-21).
"""
from datetime import datetime, timedelta

from core.tz import IST
from saarthi.Models import Chunk
from saarthi.calendar_ import compute_free_windows
from saarthi.config import DEFAULT_CONFIG
from saarthi.packer import pack
from services.cpsat_bridge import timetable_events


def test_no_chunk_overlaps_a_class():
    start = datetime(2026, 8, 21, 8, 0, tzinfo=IST)   # Friday, before classes
    horizon_end = start + timedelta(days=DEFAULT_CONFIG.horizon_days)

    classes = timetable_events(start, horizon_end)
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
