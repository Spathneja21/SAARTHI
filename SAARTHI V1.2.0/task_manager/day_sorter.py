import pandas as pd
from datetime import datetime, timedelta
import os

# Only importing the handlers now — no flexibility sorter here
from task_manager.assigner import today, tomorrow, later

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

    today = datetime.now().date()
    tomorrow = today + timedelta(days=1)

    print(f"🧭 System date: {today}")
    print("\n📄 Preview of loaded tasks:")
    print(df[['task_name', 'deadline', 'priority']])

    today_df = df[df['deadline'].dt.date == today]
    tomorrow_df = df[df['deadline'].dt.date == tomorrow]
    later_df = df[df['deadline'].dt.date > tomorrow]

    print("\n📊 Split Summary:")
    print(f"🟢 Today: {len(today_df)} task(s)")
    print(f"🟡 Tomorrow: {len(tomorrow_df)} task(s)")
    print(f"🔵 Later: {len(later_df)} task(s)\n")

    return today_df, tomorrow_df, later_df

def save_raw(df, name, data_dir):
    if df is None or df.empty:
        print(f"⚠️ No tasks for '{name}', skipping.\n")
        return pd.DataFrame()

    path = os.path.join(data_dir, f"{name}_tasks.csv")
    try:
        df.to_csv(path, index=False)
        print(f"📁 ✅ Saved raw {name} tasks to: {path}")
    except Exception as e:
        print(f"❌ Error writing {name} tasks: {e}")

    return df

def main():
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "data")
    task_file = os.path.join(data_dir, "etasks.csv")

    today_df, tomorrow_df, later_df = split_tasks_by_day(task_file)

    today_df = save_raw(today_df, "today", data_dir)
    tomorrow_df = save_raw(tomorrow_df, "tomorrow", data_dir)
    later_df = save_raw(later_df, "later", data_dir)

    if not today_df.empty:
        today.handle(today_df)
    if not tomorrow_df.empty:
        tomorrow.handle(tomorrow_df)
    if not later_df.empty:
        later.handle(later_df)
    
        # ✅ Combine updated_today/tomorrow/later into etasks_updated.csv
    print("\n🔄 Combining updated day-wise files into etasks_updated.csv...")

    updated_files = ["updated_today.csv", "updated_tomorrow.csv", "updated_later.csv"]
    updated_dfs = []

    for fname in updated_files:
        fpath = os.path.join(data_dir, fname)
        if os.path.exists(fpath):
            try:
                df = pd.read_csv(fpath)
                updated_dfs.append(df)
                print(f"📄 Added {fname}")
            except Exception as e:
                print(f"⚠️ Error reading {fname}: {e}")
        else:
            print(f"⚠️ File not found: {fname}")

    if updated_dfs:
        full_df = pd.concat(updated_dfs, ignore_index=True)
        full_path = os.path.join(data_dir, "etasks_updated.csv")
        full_df.to_csv(full_path, index=False)
        print(f"✅ Saved all updated tasks to: {full_path}")
    else:
        print("❌ No updated files found to combine.")

    

if __name__ == "__main__":
    main()
