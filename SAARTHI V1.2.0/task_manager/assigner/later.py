import os
import pandas as pd
from . import flexibility_sorter

def handle(df):
    print("📆 Handling LATER tasks...")

    updated_df = flexibility_sorter.process_flexibility(df)

    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_later.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated later tasks saved at: {updated_path}")

def assign_later_tasks(df):
    print("🧠 Assigning LATER tasks using AI strategy...")

    # Placeholder strategy
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    output_path = os.path.join(data_dir, "assigned_later.csv")

    df.to_csv(output_path, index=False)
    print(f"📌 Assigned later tasks saved at: {output_path}")
