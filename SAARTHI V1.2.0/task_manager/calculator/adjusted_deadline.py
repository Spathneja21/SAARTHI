from datetime import datetime, timedelta
import pandas as pd
import os

def minutes_to_hhmm(minutes):
    minutes = int(minutes)
    return f"{minutes // 60}:{minutes % 60:02d}"

def compute_adjusted_deadline_diff_verbose(df):
    now = datetime.now()

    # Build path to combined.csv using os
    base_dir = os.path.dirname(__file__)                  # task_manager/calculator/
    data_dir = os.path.join(base_dir, "..", "data")       # task_manager/data/
    combined_path = os.path.join(data_dir, "combined.csv")

    occupied_df = pd.read_csv(combined_path)
    occupied_df['Start'] = pd.to_datetime(occupied_df['Start'])
    occupied_df['End'] = pd.to_datetime(occupied_df['End'])

    for idx, row in df.iterrows():
        deadline = pd.to_datetime(row['deadline'])

        # Get all occupied blocks between now and deadline
        occupied_between = occupied_df[
            (occupied_df['Start'] >= now) & 
            (occupied_df['End'] <= deadline)
        ]

        total_occupied_minutes = 0
        for _, block in occupied_between.iterrows():
            duration = (block['End'] - block['Start']).total_seconds() / 60
            total_occupied_minutes += duration

        raw_diff_minutes = (deadline - now).total_seconds() / 60
        adjusted_diff_minutes = raw_diff_minutes - total_occupied_minutes

        df.at[idx, 'current_time'] = now.strftime("%H:%M")
        df.at[idx, 'deadline_diff'] = minutes_to_hhmm(raw_diff_minutes)
        df.at[idx, 'occupied_time'] = minutes_to_hhmm(total_occupied_minutes)
        df.at[idx, 'adjusted_deadline_diff'] = minutes_to_hhmm(adjusted_diff_minutes)

        if adjusted_diff_minutes < 0:
            print(f"⚠️ You dont have enough time for: {row['task_name']}")

    return df

