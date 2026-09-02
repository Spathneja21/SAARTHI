from datetime import datetime, timedelta
from saarthi.Models import FixedEvent, FreeWindow
from saarthi.config import SchedulerConfig, DEFAULT_CONFIG


def compute_free_windows(
    fixed_events: list[FixedEvent],
    horizon_start: datetime,
    horizon_end: datetime,
    config: SchedulerConfig = DEFAULT_CONFIG,
) -> list[FreeWindow]:
    """
    Algorithm:
    1. Add out-of-day-hours as synthetic blocked events
    2. Sort and merge all blocked events
    3. Invert: gaps between merged blocks = free windows
    4. Filter: drop windows shorter than min_window_minutes
    """

    # Step 1: build list of all blocked periods
    blocked = list(fixed_events)

    cursor = horizon_start.replace(hour=0, minute=0, second=0, microsecond=0)
    while cursor < horizon_end:
        day_start = cursor.replace(hour=config.day_start_hour, minute=0)
        day_end   = cursor.replace(hour=config.day_end_hour,   minute=0)
        next_day  = cursor + timedelta(days=1)

        # Block: midnight → day_start_hour (before day begins)
        if cursor < day_start:
            blocked.append(FixedEvent("night_start", "out-of-hours", cursor, day_start))

        # Block: day_end_hour → next midnight (after day ends)
        blocked.append(FixedEvent("night_end", "out-of-hours", day_end, next_day))

        cursor = next_day

    # Clip all blocked events to the horizon
    clipped = []
    for evt in blocked:
        s = max(evt.start, horizon_start)
        e = min(evt.end,   horizon_end)
        if s < e:
            clipped.append((s, e))

    # Step 2: sort and merge overlapping blocks
    clipped.sort(key=lambda x: x[0])
    merged = []
    for s, e in clipped:
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))

    # Step 3: invert — gaps between merged blocks are free windows
    windows = []
    prev_end = horizon_start
    for block_start, block_end in merged:
        if block_start > prev_end:
            windows.append(FreeWindow(prev_end, block_start))
        prev_end = max(prev_end, block_end)
    if prev_end < horizon_end:
        windows.append(FreeWindow(prev_end, horizon_end))

    # Step 4: filter tiny slivers
    min_duration = timedelta(minutes=config.min_window_minutes)
    windows = [w for w in windows if w.duration >= min_duration]

    return windows


def invert_windows(
    free_windows: list[FreeWindow],
    horizon_start: datetime,
    horizon_end: datetime,
) -> list[FreeWindow]:
    """Return the complement: periods that are NOT free. Used by packer."""
    blocked = []
    prev_end = horizon_start
    for w in sorted(free_windows, key=lambda x: x.start):
        if w.start > prev_end:
            blocked.append(FreeWindow(prev_end, w.start))
        prev_end = max(prev_end, w.end)
    if prev_end < horizon_end:
        blocked.append(FreeWindow(prev_end, horizon_end))
    return blocked
