# import os
# import pandas as pd
# from . import flexibility_sorter
# from task_manager.assigner import rigid_today

# def handle(df):
#     print("📆 Handling TODAY's tasks...")

#     updated_df = flexibility_sorter.process_flexibility(df)

#     base_dir = os.path.dirname(os.path.dirname(__file__))
#     data_dir = os.path.join(base_dir, "data")
#     updated_path = os.path.join(data_dir, "updated_today.csv")

#     updated_df.to_csv(updated_path, index=False)
#     print(f"✅ Updated today tasks saved at: {updated_path}")

# def assign_today_tasks(df):
#     print("🧠 Assigning TODAY tasks using AI strategy...")

#     # Base paths
#     base_dir = os.path.dirname(os.path.dirname(__file__))
#     data_dir = os.path.join(base_dir, "data")
#     output_path = os.path.join(data_dir, "assigned_today.csv")

#     # Filter: Only keep tasks with a positive adjusted deadline difference
#     df = df[df['adjusted_deadline_diff'] > 0].copy()
#     if df.empty:
#         print("⚠️ No tasks can be scheduled today (all are overdue).")
#         return

#     # Filter for rigid tasks
#     rigid_tasks = df[df['flexibility'] == 'rigid']

#     if not rigid_tasks.empty:
#         print(f"🔒 Assigning {len(rigid_tasks)} rigid task(s)...")
#         rigid_result = rigid_today.assign(rigid_tasks)
#     else:
#         print("❗ No rigid tasks found.")
#         rigid_result = pd.DataFrame()

#     # Save the assigned rigid tasks
#     if not rigid_result.empty:
#         rigid_result.to_csv(output_path, index=False)
#         print(f"📌 Assigned rigid today tasks saved at: {output_path}")
#     else:
#         print("📭 No rigid tasks were assigned.")

import os
import pandas as pd
from . import flexibility_sorter
from task_manager.assigner import rigid_today


def handle(df):
    print("📆 Handling TODAY's tasks...")

    # Apply flexibility logic
    updated_df = flexibility_sorter.process_flexibility(df)

    # Save updated today file with flexibility info
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_today.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated today tasks saved at: {updated_path}")


def assign_today_tasks(df):
    print("🧠 Assigning TODAY tasks using AI strategy...")

    # Setup paths
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    output_path = os.path.join(data_dir, "assigned_today.csv")

    # Step 1: Filter only tasks with time left
    df = df[df['adjusted_deadline_diff'] > 0].copy()
    if df.empty:
        print("⚠️ No tasks can be scheduled today (all are overdue).")
        return

    # Step 2: Filter rigid tasks only (for now)
    rigid_tasks = df[df['flexibility'] == 'rigid']
    print(rigid_tasks)
    if not rigid_tasks.empty:
        print(f"🔒 Assigning {len(rigid_tasks)} rigid task(s)...")
        rigid_result = rigid_today.assign(rigid_tasks)
    else:
        print("❗ No rigid tasks found for today.")
        rigid_result = pd.DataFrame()

    # Step 3: Save assigned rigid tasks if any
    if not rigid_result.empty:
        rigid_result.to_csv(output_path, index=False)
        print(f"📌 Assigned rigid today tasks saved at: {output_path}")
    else:
        print("📭 No rigid tasks were assigned.")
