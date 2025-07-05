import pandas as pd
from datetime import datetime, timedelta
import os

# Import the flexibility sorter and per-day handler scripts
from task_manager.assigner import flexibility_sorter, today, tomorrow, later

def split_tasks_by_day(task_file_path):
    print(f"📥 Reading from: {task_file_path}")

    if not os.path.exists(task_file_path):
        print("❌ etasks.csv not found at path!")
        return None, None, None

    df = pd.read_csv(task_file_path)

    # Convert deadline to datetime
    df['deadline'] = pd.to_datetime(df['deadline'], errors='coerce')
    if df['deadline'].isnull().any():
        print("⚠️ Warning: Some deadlines could not be parsed.\n")

    # Print current system date
    today = datetime.now().date()
    tomorrow = today + timedelta(days=1)

    print(f"🧭 System date: {today}")
    print("\n📄 Preview of loaded tasks:")
    print(df[['task_name', 'deadline', 'priority']])

    # Split tasks by deadline
    today_df = df[df['deadline'].dt.date == today]
    tomorrow_df = df[df['deadline'].dt.date == tomorrow]
    later_df = df[df['deadline'].dt.date > tomorrow]

    print("\n📊 Split Summary:")
    print(f"🟢 Today: {len(today_df)} task(s)")
    print(f"🟡 Tomorrow: {len(tomorrow_df)} task(s)")
    print(f"🔵 Later: {len(later_df)} task(s)\n")

    return today_df, tomorrow_df, later_df

def save_and_process(df, name, data_dir):
    if df is None or df.empty:
        print(f"⚠️ No tasks for '{name}', skipping processing.\n")
        return pd.DataFrame()

    raw_path = os.path.join(data_dir, f"{name}_tasks.csv")
    updated_path = os.path.join(data_dir, f"updated_{name}.csv")

    # Save original filtered file
    df.to_csv(raw_path, index=False)
    print(f"📁 Saved raw tasks to: {raw_path}")

    # Add flexibility
    updated_df = flexibility_sorter.process_flexibility(df)

    # Save updated file
    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Saved updated (with flexibility) to: {updated_path}\n")

    return updated_df

def main():
    base_dir = os.path.dirname(__file__)            # .../task_manager
    data_dir = os.path.join(base_dir, "data")        # .../task_manager/data
    task_file = os.path.join(data_dir, "etasks.csv")

    # Split tasks
    today_df, tomorrow_df, later_df = split_tasks_by_day(task_file)

    # Process each group
    updated_today = save_and_process(today_df, "today", data_dir)
    updated_tomorrow = save_and_process(tomorrow_df, "tomorrow", data_dir)
    updated_later = save_and_process(later_df, "later", data_dir)

    # Hand over to strategy handlers
    if not updated_today.empty:
        today.handle(updated_today)
    if not updated_tomorrow.empty:
        tomorrow.handle(updated_tomorrow)
    if not updated_later.empty:
        later.handle(updated_later)

if __name__ == "__main__":
    main()
