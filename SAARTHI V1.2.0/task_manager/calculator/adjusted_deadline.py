# task_manager/calculator/adjusted_deadline.py

import pandas as pd
from datetime import datetime
import os

def compute_adjusted_deadline_diff_verbose(df):
    now = datetime.now().replace(second=0, microsecond=0)
    current_time_str = now.strftime("%H:%M")

    # Load combined schedule (sleep, fixed, food)
    base_dir = os.path.dirname(os.path.dirname(__file__))
    combined_path = os.path.join(base_dir, "data", "combined.csv")
    combined = pd.read_csv(combined_path)

    results = []

    for _, row in df.iterrows():
        deadline = pd.to_datetime(row['deadline'])
        task_name = row['task_name']
        duration = row['duration']
        priority = row['priority']
        flexibility = row['flexibility']

        # Raw diff in HOURS
        raw_diff_hours = (deadline - now).total_seconds() / 3600

        # Get day name
        day_of_deadline = deadline.strftime("%A")

        # Calculate occupied time in HOURS
        occupied_hours = 0
        for _, block in combined.iterrows():
            if block['Day'] != day_of_deadline:
                continue

            start = datetime.strptime(block['Start'], "%H:%M")
            end = datetime.strptime(block['End'], "%H:%M")

            start_dt = deadline.replace(hour=start.hour, minute=start.minute)
            end_dt = deadline.replace(hour=end.hour, minute=end.minute)

            if end_dt <= now or start_dt >= deadline:
                continue

            overlap_start = max(now, start_dt)
            overlap_end = min(deadline, end_dt)

            block_hours = (overlap_end - overlap_start).total_seconds() / 3600
            occupied_hours += block_hours

        adjusted_diff_hours = raw_diff_hours - occupied_hours

        results.append({
            "task_name": task_name,
            "duration": duration,
            "deadline": deadline.strftime("%Y-%m-%d %H:%M"),
            "priority": priority,
            "flexibility": flexibility,
            "current_time": current_time_str,
            "raw_deadline_diff": round(raw_diff_hours, 2),
            "occupied_time_between": round(occupied_hours, 2),
            "adjusted_deadline_diff": round(adjusted_diff_hours, 2)
        })

    return pd.DataFrame(results)
