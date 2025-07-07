from . import flexibility_sorter
import os
import pandas as pd

def handle(df: pd.DataFrame):
    print("📆 Handling TODAY's tasks...")

    # Apply flexibility tagging
    updated_df = flexibility_sorter.process_flexibility(df)

    # Construct data directory path
    base_dir = os.path.dirname(os.path.dirname(__file__))  # go back to task_manager/
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_today.csv")

    # Ensure the directory exists
    os.makedirs(data_dir, exist_ok=True)

    try:
        updated_df.to_csv(updated_path, index=False)
        print(f"✅ Updated today tasks saved at: {updated_path}")
    except Exception as e:
        print(f"❌ Error while saving updated_today.csv: {e}")
