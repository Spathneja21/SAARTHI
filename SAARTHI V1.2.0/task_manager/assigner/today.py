import os
import pandas as pd
from . import flexibility_sorter
from task_manager.assigner import assign_today
from task_manager.calculator.adjusted_deadline import compute_adjusted_deadline_diff_verbose


def handle(df):
    print("📆 Handling TODAY's tasks...")

    # Apply flexibility logic
    updated_df = flexibility_sorter.process_flexibility(df)

    # Save updated today file with flexibility info
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_today.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated today tasks saved at: {updated_path}")




def assign_today_tasks(_df=None):
    print("🧠 Preparing TODAY tasks for assignment...")

    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_today.csv")
    assign_path = os.path.join(data_dir, "updated_today_assign.csv")

    if not os.path.exists(updated_path):
        print(f"❌ File not found: {updated_path}")
        return

    df = pd.read_csv(updated_path)
    if df.empty:
        print("⚠️ updated_today.csv is empty.")
        return

    df = compute_adjusted_deadline_diff_verbose(df)
    df["adjusted_deadline_diff"] = df["adjusted_deadline_diff"].round(2)

    df.to_csv(assign_path, index=False)
    print(f"✅ Updated today assignment file saved at: {assign_path}")

    assign_today.assign()