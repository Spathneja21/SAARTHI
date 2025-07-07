from . import flexibility_sorter
import os
import pandas as pd

def handle(df):
    print("📆 Handling LATER tasks...")

    # Apply flexibility logic
    updated_df = flexibility_sorter.process_flexibility(df)

    # Save the updated file
    base_dir = os.path.dirname(os.path.dirname(__file__))  # go back to task_manager/
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_later.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated later tasks saved at: {updated_path}")
    
