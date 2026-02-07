import os
import pandas as pd
from task_manager.assigner import rigid_today


def assign():
    print("🧠 Assigning TODAY tasks from updated_today_assign.csv...")

    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    input_path = os.path.join(data_dir, "updated_today_assign.csv")
    output_path = os.path.join(data_dir, "assigned_today.csv")

    if not os.path.exists(input_path):
        print(f"❌ File not found: {input_path}")
        return

    df = pd.read_csv(input_path)
    if df.empty:
        print("⚠️ No tasks to assign in updated_today_assign.csv.")
        return

    df = df[df["adjusted_deadline_diff"] > 0].copy()
    if df.empty:
        print("⚠️ No tasks can be scheduled today (all are overdue).")
        return

    rigid_tasks = df[df["flexibility"] == "rigid"]
    if not rigid_tasks.empty:
        print(f"🔒 Assigning {len(rigid_tasks)} rigid task(s)...")
        rigid_result = rigid_today.assign(rigid_tasks)
    else:
        print("❗ No rigid tasks found for today.")
        rigid_result = pd.DataFrame()
