import os
import pandas as pd
from . import flexibility_sorter

def handle(df):
    print("📆 Handling TODAY's tasks...")

    updated_df = flexibility_sorter.process_flexibility(df)

    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_today.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated today tasks saved at: {updated_path}")

def assign_today_tasks(df):
    print("🧠 Assigning TODAY tasks using AI strategy...")

    # Placeholder strategy — just saving assigned tasks for now
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    output_path = os.path.join(data_dir, "assigned_today.csv")

    df.to_csv(output_path, index=False)
    print(f"📌 Assigned today tasks saved at: {output_path}")
