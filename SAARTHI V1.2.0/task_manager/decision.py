# from datetime import datetime, timedelta
# import pandas as pd
# from task_manager.calculator import occupied_blocks

# def compute_adjusted_deadline_diff_verbose(df):
#     now = datetime.now()
#     occupied_df = occupied_blocks.get_occupied_blocks()

#     df['deadline'] = pd.to_datetime(df['deadline'], errors='coerce')

#     # Initialize new columns
#     current_times = []
#     raw_diffs = []
#     occupied_times = []
#     adjusted_diffs = []

#     for _, task in df.iterrows():
#         task_name = task['task_name']
#         deadline = task['deadline']

#         if pd.isna(deadline):
#             print(f"⚠️ Skipping task '{task_name}' due to invalid deadline.")
#             current_times.append(None)
#             raw_diffs.append(None)
#             occupied_times.append(None)
#             adjusted_diffs.append(None)
#             continue

#         current_times.append(now)
#         raw_diff = deadline - now
#         raw_diffs.append(raw_diff)

#         # Filter overlapping occupied blocks
#         overlaps = occupied_df[
#             (pd.to_datetime(occupied_df['End']) > now) &
#             (pd.to_datetime(occupied_df['Start']) < deadline)
#         ]

#         total_occupied = timedelta()
#         for _, block in overlaps.iterrows():
#             overlap_start = max(pd.to_datetime(block['Start']), now)
#             overlap_end = min(pd.to_datetime(block['End']), deadline)
#             total_occupied += max(overlap_end - overlap_start, timedelta())

#         occupied_times.append(total_occupied)
#         adjusted_diff = raw_diff - total_occupied
#         adjusted_diffs.append(adjusted_diff.total_seconds() / 3600)

#     # Add all the columns to the dataframe
#     df['current_time'] = current_times
#     df['raw_deadline_diff'] = [d.total_seconds() / 3600 if d else None for d in raw_diffs]
#     df['occupied_time_between'] = [d.total_seconds() / 3600 if d else None for d in occupied_times]
#     df['adjusted_deadline_diff'] = adjusted_diffs

#     return df
import pandas as pd
from task_manager.calculator.adjusted_deadline import compute_adjusted_deadline_diff_verbose
import os 
def main():
    base_dir = os.path.dirname(__file__)  # task_manager/
    data_dir = os.path.join(base_dir, "data")
    task_path = os.path.join(data_dir, "etasks_updated.csv")

    if not os.path.exists(task_path):
        print("❌ 'etasks_updated.csv' not found! Please ensure flexibility is processed before decision.")
        return

    df = pd.read_csv(task_path)

    df = compute_adjusted_deadline_diff_verbose(df)

    # Now you can use df['adjusted_deadline_diff'] to make decisions
    print(df[['task_name', 'current_time', 'deadline_diff', 'occupied_time', 'adjusted_deadline_diff']])
