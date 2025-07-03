import pandas as pd
from datetime import datetime, timedelta
import os

def expand_to_5_min_slots(day, start_str, end_str, task):
    fmt = "%H:%M"
    start_time = datetime.strptime(str(start_str), fmt)
    end_time = datetime.strptime(str(end_str), fmt)

    slots = []
    current = start_time
    while current < end_time:
        slot_end = current + timedelta(minutes=5)
        slots.append({
            "Day": day,
            "Start": current.strftime("%H:%M"),
            "End": slot_end.strftime("%H:%M"),
            "Task": task
        })
        current = slot_end
    return slots

def expand_combined_csv():
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "..", "data")
    combined_csv = os.path.join(data_dir, "combined.csv")
    df = pd.read_csv(combined_csv)

    expanded = []
    for _, row in df.iterrows():
        if pd.isna(row['Start']) or pd.isna(row['End']):
            continue
        expanded.extend(expand_to_5_min_slots(row['Day'], row['Start'], row['End'], row['Task']))

    expanded_df = pd.DataFrame(expanded)
    expanded_df.to_csv(os.path.join(data_dir, "expanded.csv"), index=False)
    print("✅ Expanded schedule written to 'expanded.csv'")



