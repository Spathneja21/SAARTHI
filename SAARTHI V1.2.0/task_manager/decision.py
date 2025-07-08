# task_manager/decision.py

import os
import pandas as pd

# Load modules from calculator
from task_manager.calculator import occupied_blocks, scheduled_records

def main():
    print("\n🧠 Starting Task Strategy Decision Engine...")

    # === Step 1: Load and preview etasks_updated.csv ===
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "data")
    updated_task_file = os.path.join(data_dir, "etasks_updated.csv")

    if not os.path.exists(updated_task_file):
        print("❌ etasks_updated.csv not found.")
        return

    tasks_df = pd.read_csv(updated_task_file)

    if tasks_df.empty:
        print("⚠️ etasks_updated.csv is empty.")
        return

    print(f"📥 Loaded {len(tasks_df)} tasks from etasks_updated.csv")
    print("📄 Columns:", list(tasks_df.columns))
    print("🔍 First 3 tasks:")
    print(tasks_df.head(3))

    # === Step 2: Load calculator data ===
    print("\n📚 Loading occupied blocks and schedule record...")
    occupied_df = occupied_blocks.get_occupied_blocks()
    schedule_df = scheduled_records.build_schedule_record()

    print(f"✅ Occupied blocks loaded: {len(occupied_df)}")
    print(f"✅ Full schedule loaded: {len(schedule_df)}\n")

    print(schedule_df)
    # === Step 3: Strategy Logic Placeholder ===
    print("🧪 Strategy logic placeholder (to be implemented)...\n")
    # You can sort/filter/select tasks here in future steps.

if __name__ == "__main__":
    main()
