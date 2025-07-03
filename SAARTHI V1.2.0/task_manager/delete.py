import pandas as pd
import os
from difflib import get_close_matches
csv_path = os.path.join(os.path.dirname(__file__), "data", "etasks.csv")

def delete_task(filepath=csv_path):
    try:
        df = pd.read_csv(filepath)
    except FileNotFoundError:
        print("⚠️ Task file not found.")
        return

    if df.empty:
        print("📭 No tasks to delete.")
        return

    # Show current tasks
    print("\n🗂️ Current tasks:")
    print(df[["task_name", "deadline"]])

    task_input = input("\n🗑️ Enter the task name you want to remove:\n> ").strip().lower()

    # Match the closest task using fuzzy match
    task_names = df["task_name"].astype(str).str.lower().tolist()
    matches = get_close_matches(task_input, task_names, n=1, cutoff=0.5)

    if not matches:
        print(f"⚠️ No close match found for '{task_input}' in '{filepath}'.")
        return

    matched_task = matches[0]
    print(f"✅ Matched with: '{matched_task}'")

    # Confirm
    confirm = input(f"Are you sure you want to remove '{matched_task}'? (y/n): ").strip().lower()
    if confirm != 'y':
        print("❌ Task removal cancelled.")
        return

    # Remove task
    df = df[df["task_name"].str.lower() != matched_task]
    df.to_csv(filepath, index=False)
    print(f"✅ Task '{matched_task}' removed successfully.")

delete_task()