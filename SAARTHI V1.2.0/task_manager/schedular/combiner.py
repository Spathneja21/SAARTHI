# task_manager/schedular/combiner.py
import pandas as pd
import os

def combine_csv():
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "..", "data")

    fixed = pd.read_csv(os.path.join(data_dir, "fixed_tasks.csv"))
    sleep = pd.read_csv(os.path.join(data_dir, "sleep.csv"))

    # Ensure both have consistent columns
    fixed = fixed[["Day", "Start", "End", "Task"]]
    sleep = sleep[["Day", "Start", "End", "Task"]]

    combined = pd.concat([fixed, sleep], ignore_index=True)

    # Drop rows with missing values
    combined = combined.dropna(subset=["Day", "Start", "End", "Task"])

    combined.to_csv(os.path.join(data_dir, "combined.csv"), index=False)
    print("✅ Combined schedule written to 'combined.csv'")
