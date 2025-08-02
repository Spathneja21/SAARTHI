import os
import pandas as pd
from datetime import datetime, timedelta
import numpy as np
from pyarrow import duration

def load_today_tasks():
    base_dir = os.path.dirname(__file__)
    file_path = os.path.join(base_dir, "../data/updated_today.csv")  # Adjusted path
    if os.path.exists(file_path):
        return pd.read_csv(file_path)
    else:
        print(f"❌ File not found: {file_path}")
        return pd.DataFrame()

def get_rigid_tasks(df):
    rigid_df = df[df['task_type'] == 'rigid']
    print(f"🧱 Rigid tasks count: {rigid_df.shape[0]}")
    return rigid_df

def assign_rigid(tasks):
    print("\n🔒 Assigning RIGID tasks...")

    # Step 1: Filter tasks with adjusted_deadline_diff > 0
    valid_tasks = [task for task in tasks if task.get('adjusted_deadline_diff', 0) > 0]

    if not valid_tasks:
        print("⚠️ No valid rigid tasks with positive ADD.")
        return

    # Step 2: Show number of valid tasks
    print(f"✅ {len(valid_tasks)} valid rigid task(s) with positive ADD.")

    # Step 3: Compute mean duration using NumPy
    durations = [task.get('duration', 0) for task in valid_tasks]
    mean_duration = np.mean(durations)
    print(f"⏱️ Mean Duration of Valid Rigid Tasks: {mean_duration:.2f} minutes")

    # Step 4: Only assign if more than 2 valid rigid tasks
    if len(valid_tasks) > 2:
        if mean_duration > 3:
            print("First branch.")
        else:
            print("First branch second option.")
        
    else:
        print("Second branch.")

def assign_flexible(task):
    print(f"🎈 Flexible task assigned: {task['task_name']}")

def assign_semi_flexible(task):
    print(f"🌀 Semi-flexible task assigned: {task['task_name']}")

def assign(df):
    print("\n🧠 Grouping tasks from assigner_today.py...")

    tasks_grouped = {
        'rigid': [],
        'flexible': [],
        'semi-flexible': [],
        'unknown': []
    }

    # Step 1: Group tasks by flexibility
    for _, row in df.iterrows():
        flexibility = str(row.get('flexibility', '')).strip().lower()

        if flexibility in tasks_grouped:
            tasks_grouped[flexibility].append(row)
        else:
            tasks_grouped['unknown'].append(row)

    # Step 2: Assign each category
    print("\n🔒 RIGID TASKS:")
    assign_rigid(tasks_grouped['rigid'])


    print("\n🎈 FLEXIBLE TASKS:")
    for task in tasks_grouped['flexible']:
        assign_flexible(task)

    print("\n🌀 SEMI-FLEXIBLE TASKS:")
    for task in tasks_grouped['semi-flexible']:
        assign_semi_flexible(task)

    if tasks_grouped['unknown']:
        print("\n⚠️ UNKNOWN FLEXIBILITY TASKS FOUND:")
        for task in tasks_grouped['unknown']:
            print(f"❓ {task.get('task_name')} – {task.get('flexibility')}")
