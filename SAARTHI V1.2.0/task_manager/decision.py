# import os
# import pandas as pd
# from datetime import datetime
# from task_manager.calculator.adjusted_deadline import compute_adjusted_deadline_diff_verbose

# def main():
#     base_dir = os.path.dirname(__file__)
#     data_dir = os.path.join(base_dir, "data")

#     # File paths
#     today_path = os.path.join(data_dir, "updated_today.csv")
#     tomorrow_path = os.path.join(data_dir, "updated_tomorrow.csv")
#     later_path = os.path.join(data_dir, "updated_later.csv")

#     # Process today's tasks
#     if os.path.exists(today_path):
#         today_df = pd.read_csv(today_path)
#         today_df['deadline'] = pd.to_datetime(today_df['deadline'])
#         today_df = compute_adjusted_deadline_diff_verbose(today_df)
#         if not today_df.empty:
#             print("\n📅 Handling TODAY tasks...")
#             print(today_df[['task_name', 'duration', 'deadline', 'priority', 'flexibility',
#                             'current_time', 'raw_deadline_diff', 'occupied_time_between', 'adjusted_deadline_diff']])
#             # 🔄 AI Strategy for today tasks goes here

#     # Process tomorrow's tasks
#     if os.path.exists(tomorrow_path):
#         tomorrow_df = pd.read_csv(tomorrow_path)
#         tomorrow_df['deadline'] = pd.to_datetime(tomorrow_df['deadline'])
#         tomorrow_df = compute_adjusted_deadline_diff_verbose(tomorrow_df)
#         if not tomorrow_df.empty:
#             print("\n📅 Handling TOMORROW tasks...")
#             print(tomorrow_df[['task_name', 'duration', 'deadline', 'priority', 'flexibility',
#                                'current_time', 'raw_deadline_diff', 'occupied_time_between', 'adjusted_deadline_diff']])
#             # 🔄 AI Strategy for tomorrow tasks goes here

#     # Process later tasks
#     if os.path.exists(later_path):
#         later_df = pd.read_csv(later_path)
#         later_df['deadline'] = pd.to_datetime(later_df['deadline'])
#         later_df = compute_adjusted_deadline_diff_verbose(later_df)
#         if not later_df.empty:
#             print("\n📅 Handling LATER tasks...")
#             print(later_df[['task_name', 'duration', 'deadline', 'priority', 'flexibility',
#                             'current_time', 'raw_deadline_diff', 'occupied_time_between', 'adjusted_deadline_diff']])
#             # 🔄 AI Strategy for later tasks goes here

# if __name__ == "__main__":
#     main()

import pandas as pd
import os
from task_manager.calculator.adjusted_deadline import compute_adjusted_deadline_diff_verbose
from task_manager.assigner import today, tomorrow, later

def read_updated_csv(filename):
    base_dir = os.path.dirname(__file__)
    file_path = os.path.join(base_dir, "data", filename)
    if os.path.exists(file_path):
        df = pd.read_csv(file_path)
        print(f"\n📄 Loaded: {filename} ({len(df)} task(s))")
        return df
    else:
        print(f"❌ File not found: {file_path}")
        return pd.DataFrame()

def process_tasks(df, label, assign_function):
    if df.empty:
        print(f"⚠️ No tasks to process for {label}.")
        return

    print(f"\n📅 Handling {label.upper()} tasks...")

    # Compute detailed adjusted deadline diff
    df = compute_adjusted_deadline_diff_verbose(df)

    # Rearranged to avoid minute confusion
    df['adjusted_deadline_diff'] = df['adjusted_deadline_diff'].round(2)

    # Display results
    print(df[['task_name', 'duration', 'deadline', 'priority', 'flexibility',
              'current_time', 'raw_deadline_diff', 'occupied_time_between', 'adjusted_deadline_diff']])

    # Handle tasks where time is insufficient
    late_tasks = df[df['adjusted_deadline_diff'] < 0]
    if not late_tasks.empty:
        print("\n⚠️ These tasks may not have enough time left:")
        print(late_tasks[['task_name', 'deadline', 'adjusted_deadline_diff']])

    # Pass to specific assignment handler
    assign_function(df)

def main():
    # Step 1: Load updated task files
    today_df = read_updated_csv("updated_today.csv")
    tomorrow_df = read_updated_csv("updated_tomorrow.csv")
    later_df = read_updated_csv("updated_later.csv")

    # Step 2: Process and assign tasks for each category
    if not today_df.empty:
        process_tasks(today_df, "today", today.assign_today_tasks)

    if not tomorrow_df.empty:
        process_tasks(tomorrow_df, "tomorrow", tomorrow.assign_tomorrow_tasks)

    if not later_df.empty:
        process_tasks(later_df, "later", later.assign_later_tasks)

if __name__ == "__main__":
    main()
