"""
Demo: add tasks interactively and watch the schedule update.
Usage: python demo.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime, timedelta
from saarthi.Models import FixedEvent, Task
from saarthi.scheduler import Scheduler
from saarthi.config import DEFAULT_CONFIG


def main():
    now = datetime.now().replace(second=0, microsecond=0)
    today = now.date()

    def dt(h, m=0, days=0):
        return datetime(today.year, today.month, today.day, h, m) + timedelta(days=days)

    print("\n" + "="*60)
    print("  SAARTHI — Scheduling Demo")
    print("="*60)

    # ── 1. Set up a sample calendar ─────────────────────────────
    sc = Scheduler(DEFAULT_CONFIG)
    fixed_events = [
        FixedEvent("e1", "Morning standup",   dt(9, 30), dt(10, 0)),
        FixedEvent("e2", "Lunch",             dt(13, 0), dt(14, 0)),
        FixedEvent("e3", "Team review",       dt(16, 0), dt(17, 0)),
    ]
    sc.set_calendar(fixed_events, now=now)
    print(f"\nCalendar set. Free windows computed from {now.strftime('%H:%M')} today.\n")

    # ── 2. Add first task ────────────────────────────────────────
    t1 = Task.create(
        name="Write project report",
        duration_minutes=180,
        deadline=dt(18),
        focus_limit_minutes=60,
        flexible=True,
    )
    print(f"Adding task: '{t1.name}' | 3h | deadline 18:00 | flex=True | focus=60min")
    sc.add_task(t1, now=now)
    sc.print_schedule(now)

    # ── 3. Add second task ───────────────────────────────────────
    t2 = Task.create(
        name="Reply to emails",
        duration_minutes=30,
        deadline=dt(12),
        focus_limit_minutes=30,
        flexible=False,
    )
    print(f"Adding task: '{t2.name}' | 30min | deadline 12:00 | flex=False")
    sc.add_task(t2, now=now)
    sc.print_schedule(now)

    # ── 4. Add urgent task mid-day ───────────────────────────────
    t3 = Task.create(
        name="Urgent client call prep",
        duration_minutes=45,
        deadline=dt(11),
        focus_limit_minutes=45,
        flexible=False,
    )
    print(f"Adding task: '{t3.name}' | 45min | deadline 11:00 | URGENT")
    sc.add_task(t3, now=now)
    sc.print_schedule(now)

    # ── 5. Print any warnings ────────────────────────────────────
    warnings = sc.get_warnings()
    if warnings:
        print("Warnings:")
        for w in warnings:
            print(f"  → {w}")
    else:
        print("All tasks scheduled within deadlines.")


if __name__ == "__main__":
    main()
