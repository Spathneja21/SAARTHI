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
