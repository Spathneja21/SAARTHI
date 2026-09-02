"""Guards the IST timezone contract.

The original bug: day_start_hour/day_end_hour were applied to a UTC-aware
`now`, so the scheduler's "08:00-23:00 working day" was really 13:30-04:30
IST -- it blocked the whole morning and booked tasks past midnight.
"""
from datetime import timedelta

from core.tz import IST, now as ist_now
from saarthi.calendar_ import compute_free_windows
from saarthi.config import DEFAULT_CONFIG


def test_free_windows_stay_inside_local_day():
    start = ist_now()
    windows = compute_free_windows(
        [], start, start + timedelta(days=DEFAULT_CONFIG.horizon_days), DEFAULT_CONFIG
    )
    assert windows, "expected at least one free window"

    for w in windows:
        s = w.start.astimezone(IST)
        e = w.end.astimezone(IST)
        # Compare against absolute local-day bounds, not bare .hour — a window
        # running to 04:30 the *next* day still has hour <= 23.
        day_start = s.replace(hour=DEFAULT_CONFIG.day_start_hour, minute=0, second=0, microsecond=0)
        day_end = s.replace(hour=DEFAULT_CONFIG.day_end_hour, minute=0, second=0, microsecond=0)
        assert s >= day_start, f"window starts {s} — before local day start"
        assert e <= day_end, f"window ends {e} — past local day end {day_end}"


def test_now_is_ist():
    assert ist_now().utcoffset() == timedelta(hours=5, minutes=30)


def test_packed_chunks_stay_inside_local_day():
    """The grid is anchored at `now`, so window bounds must be quantized
    conservatively or a chunk starts just before the working day opens."""
    from saarthi.Models import Chunk
    from saarthi.packer import pack

    start = ist_now()
    horizon_end = start + timedelta(days=DEFAULT_CONFIG.horizon_days)
    chunks = [
        Chunk(
            id=f"c{i}", parent_id=f"t{i}", parent_name=f"task {i}", index=0,
            duration=timedelta(minutes=90), deadline=horizon_end,
            is_final=True, break_after=timedelta(0),
        )
        for i in range(6)
    ]
    windows = compute_free_windows([], start, horizon_end, DEFAULT_CONFIG)
    plan = pack(chunks, windows, start, horizon_end, config=DEFAULT_CONFIG)

    assert plan.assignments, "expected chunks to be scheduled"
    for a in plan.assignments:
        s = a.start.astimezone(IST)
        e = a.end.astimezone(IST)
        day_start = s.replace(hour=DEFAULT_CONFIG.day_start_hour, minute=0, second=0, microsecond=0)
        day_end = s.replace(hour=DEFAULT_CONFIG.day_end_hour, minute=0, second=0, microsecond=0)
        assert s >= day_start, f"chunk starts {s} — before local day start {day_start}"
        assert e <= day_end, f"chunk ends {e} — past local day end {day_end}"


if __name__ == "__main__":
    test_now_is_ist()
    test_free_windows_stay_inside_local_day()
    test_packed_chunks_stay_inside_local_day()
    print("ok")
