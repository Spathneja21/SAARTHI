import pandas as pd
import os

def get_occupied_blocks():
    base_dir = os.path.dirname(os.path.dirname(__file__))  # task_manager/
    data_dir = os.path.join(base_dir, "data")
    combined_path = os.path.join(data_dir, "grouped_schedule.csv")

    if not os.path.exists(combined_path):
        print("❌ combined.csv not found!")
        return pd.DataFrame()

    try:
        df = pd.read_csv(combined_path)
        df = df[["Day", "Start", "End", "Task"]]  # Standardized column set
        df = df.dropna()
        print(f"✅ Loaded occupied blocks from combined.csv ({len(df)} rows)")
        return df
    except Exception as e:
        print(f"⚠️ Error loading combined.csv: {e}")
        return pd.DataFrame()
