# from . import flexibility_sorter
# import os
# import pandas as pd

# def handle(df):
#     print("📆 Handling TOMORROW's tasks...")

#     # Apply flexibility logic
#     updated_df = flexibility_sorter.process_flexibility(df)

#     # Save the updated file
#     base_dir = os.path.dirname(os.path.dirname(__file__))  # go back to task_manager/
#     data_dir = os.path.join(base_dir, "data")
#     updated_path = os.path.join(data_dir, "updated_tomorrow.csv")

#     updated_df.to_csv(updated_path, index=False)
#     print(f"✅ Updated tomorrow tasks saved at: {updated_path}")


from . import flexibility_sorter
import os
import pandas as pd
from task_manager.calculator.adjusted_deadline import compute_adjusted_deadline_diff_verbose

def handle(df):
    print("📆 Handling TOMORROW's tasks...")

    # Apply flexibility logic
    updated_df = flexibility_sorter.process_flexibility(df)

    # Save the updated file
    base_dir = os.path.dirname(os.path.dirname(__file__))  # go back to task_manager/
    data_dir = os.path.join(base_dir, "data")
    updated_path = os.path.join(data_dir, "updated_tomorrow.csv")

    updated_df.to_csv(updated_path, index=False)
    print(f"✅ Updated tomorrow tasks saved at: {updated_path}")


def assign_tomorrow_tasks(df):
    print("\n📆 Assigning tasks for TOMORROW...")

    # Compute adjusted deadline difference and related diagnostics
    df = compute_adjusted_deadline_diff_verbose(df)

    # Sort tasks by urgency and priority
    df = df.sort_values(by=["adjusted_deadline_diff", "priority"], ascending=[True, False])

    # Show diagnostics
    print(df[['task_name', 'duration', 'deadline', 'priority', 'flexibility',
              'current_time', 'raw_deadline_diff', 'occupied_time_between', 'adjusted_deadline_diff']])

    # Warn if any tasks are impossible
    late_tasks = df[df['adjusted_deadline_diff'] < 0]
    if not late_tasks.empty:
        print("\n⚠️ The following tasks cannot be completed on time:")
        print(late_tasks[['task_name', 'deadline', 'adjusted_deadline_diff']])

    # Save the scheduled plan for tomorrow
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    scheduled_path = os.path.join(data_dir, "scheduled_tomorrow.csv")
    df.to_csv(scheduled_path, index=False)
    print(f"\n✅ Scheduled tomorrow tasks saved to: {scheduled_path}")
