# task_manager/schedular/combiner.py
import pandas as pd
import os

def combine_csv():
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "..", "data")

    # Load all files
    fixed = pd.read_csv(os.path.join(data_dir, "fixed_tasks.csv"))
    sleep = pd.read_csv(os.path.join(data_dir, "sleep.csv"))
    food = pd.read_csv(os.path.join(data_dir, "food.csv"))  # 🔥 NEW

    # Ensure all have consistent columns
    fixed = fixed[["Day", "Start", "End", "Task"]]
    sleep = sleep[["Day", "Start", "End", "Task"]]
    food = food[["Day", "Start", "End", "Task"]]  # 🔥 NEW

    # Combine all
    combined = pd.concat([fixed, sleep, food], ignore_index=True)

    # Drop rows with missing values
    combined = combined.dropna(subset=["Day", "Start", "End", "Task"])

    # Save combined schedule
    output_path = os.path.join(data_dir, "combined.csv")
    combined.to_csv(output_path, index=False)

    print("✅ Combined schedule written to 'combined.csv'")
