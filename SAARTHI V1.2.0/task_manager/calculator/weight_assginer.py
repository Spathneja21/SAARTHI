import os
import pandas as pd
import numpy as np
from datetime import datetime

# 1. Load today's task file using os
base_dir = os.path.dirname(os.path.dirname(__file__))
data_dir = os.path.join(base_dir, "data")
input_file = os.path.join(data_dir, 'today_tasks.csv')
output_file = os.path.join(data_dir, 'assigned_today.csv')

# Ensure the input file exists
if not os.path.exists(input_file):
    raise FileNotFoundError(f"Input file not found: {input_file}")

α = 2.0     # Priority weight
β = 5.0     # Urgency weight
γ = 1.5     # Duration weight

# ------------------- Main Calculation -------------------
def calculate_weight(row):
    now = datetime.now()
    deadline = pd.to_datetime(row['deadline'])
    hours_until_deadline = max((deadline - now).total_seconds() / 3600, 0.01)

    priority = row['priority']
    duration = row['duration']
    urgency = 1 / (hours_until_deadline + 1)

    weight = (α * priority) + (β * urgency) + (γ * duration)
    return round(weight, 4)

# ------------------- Run -------------------
def main():
    if not os.path.exists(input_file):
        print(f"❌ Input file not found: {input_file}")
        return

    df = pd.read_csv(input_file)

    # Validate columns
    required = {'task_name', 'duration', 'deadline', 'priority'}
    if not required.issubset(df.columns):
        print(f"❌ Missing columns in CSV. Required: {required}")
        return

    # Calculate weights
    df['weight'] = df.apply(calculate_weight, axis=1)
    print(df)
    # Save to output
    df.to_csv(output_file, index=False)
    print(f"✅ Task weights calculated and saved to: {output_file}")

if __name__ == "__main__":
    main()
