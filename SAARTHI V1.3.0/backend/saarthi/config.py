from dataclasses import dataclass

@dataclass
class SchedulerConfig:
    # Time grid
    grid_minutes: int = 15          # 1 slot = 15 minutes
    horizon_days: int = 7         # plan this many days ahead

    # Day bounds (user's active hours)
    day_start_hour: int = 8         # 08:00
    day_end_hour: int = 23          # 23:00

    # Window filtering
    min_window_minutes: int = 15    # drop free windows smaller than this

    # Break rules
    default_break_minutes: int = 10
    break_ratio: float = 0.15       # break = max(default, duration * ratio)
    max_break_minutes: int = 30     # cap on break duration

    # Elastic buffer (absorbs small overruns without re-planning)
    elastic_buffer_ratio: float = 0.08  # inflate occupied slots by 8%

    # Chunking
    orphan_chunk_threshold: float = 0.25  # fold last chunk if < 25% of focus_limit

    # CP-SAT objective weights
    # Ordering must hold: w_schedule >> w_overrun >> w_displace
    w_schedule: int = 10000         # reward per chunk scheduled
    w_overrun: int = 100            # penalty per slot of deadline overrun
    w_displace: int = 5             # penalty per slot moved from original position
    w_slot_quality: int = 50        # reward per unit of ML slot quality score

    # Solver limits
    solver_time_limit_s: float = 3.0
    solver_workers: int = 4


# Module-level default instance — import this everywhere
DEFAULT_CONFIG = SchedulerConfig()
