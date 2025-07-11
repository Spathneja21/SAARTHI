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

    # Base paths
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    output_path = os.path.join(data_dir, "assigned_today.csv")

    # Filter: Only keep tasks with a positive adjusted deadline difference
    df = df[df['adjusted_deadline_diff'] > 0].copy()
    if df.empty:
        print("⚠️ No tasks can be scheduled today (all are overdue).")
        return

    # Sort tasks by flexibility type
    rigid_tasks = df[df['flexibility'] == 'rigid']
    semi_flexible_tasks = df[df['flexibility'] == 'semi-flexible']
    flexible_tasks = df[df['flexibility'] == 'flexible']

    # Branch 1: Handle rigid tasks
    if not rigid_tasks.empty:
        print(f"🔒 Assigning {len(rigid_tasks)} rigid task(s)...")
        from task_manager.assigner import rigid_today
        rigid_result = rigid_today.assign(rigid_tasks)
    else:
        rigid_result = pd.DataFrame()

    # Branch 2: Handle semi-flexible tasks
    if not semi_flexible_tasks.empty:
        print(f"🌓 Assigning {len(semi_flexible_tasks)} semi-flexible task(s)...")
        # from task_manager.AI_models import semi_flexible_model
        # semi_flexible_model.assign(semi_flexible_tasks)
        semi_flexible_result = semi_flexible_tasks
    else:
        semi_flexible_result = pd.DataFrame()

    # Branch 3: Handle flexible tasks
    if not flexible_tasks.empty:
        print(f"🌿 Assigning {len(flexible_tasks)} flexible task(s)...")
        # from task_manager.AI_models import flexible_model
        # flexible_model.assign(flexible_tasks)
        flexible_result = flexible_tasks
    else:
        flexible_result = pd.DataFrame()

    # Combine all results
    final_df = pd.concat([rigid_result, semi_flexible_result, flexible_result])
    final_df.to_csv(output_path, index=False)
    print(f"📌 Assigned today tasks saved at: {output_path}")
