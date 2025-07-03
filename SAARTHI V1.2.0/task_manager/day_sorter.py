# import pandas as pd
# from datetime import datetime, timedelta
# import os

# def split_tasks_by_day():
#     # Build absolute path to etasks.csv relative to this file
#     base_dir = os.path.dirname(__file__)
#     task_file = os.path.join(base_dir, "..", "data", "etasks.csv")
#     output_dir = os.path.join(base_dir, "..", "data")

#     # Load task data
#     try:
#         df = pd.read_csv(task_file)
#     except FileNotFoundError:
#         print(f"❌ File not found: {task_file}")
#         return

#     df['deadline'] = pd.to_datetime(df['deadline'], errors='coerce')

#     # Get today and tomorrow
#     now = datetime.now()
#     today = now.date()
#     tomorrow = today + timedelta(days=1)

#     # Categorize tasks
#     today_df = df[df['deadline'].dt.date == today]
#     tomorrow_df = df[df['deadline'].dt.date == tomorrow]
#     later_df = df[df['deadline'].dt.date > tomorrow]

#     # Save them
#     today_df.to_csv(os.path.join(output_dir, "today_tasks.csv"), index=False)
#     tomorrow_df.to_csv(os.path.join(output_dir, "tomorrow_tasks.csv"), index=False)
#     later_df.to_csv(os.path.join(output_dir, "later_tasks.csv"), index=False)

#     print("✅ Split tasks into:")
#     print("   📁 today_tasks.csv")
#     print("   📁 tomorrow_tasks.csv")
#     print("   📁 later_tasks.csv")

#     return today_df, tomorrow_df, later_df

import pandas as pd
from datetime import datetime, timedelta
import os

def split_tasks_by_day():
    base_dir = os.path.dirname(__file__)           # task_manager/
    data_dir = os.path.join(base_dir, "data")       # task_manager/data/
    task_file = os.path.join(data_dir, "etasks.csv")

    try:
        df = pd.read_csv(task_file)
    except FileNotFoundError:
        print(f"❌ File not found: {task_file}")
        return

    df['deadline'] = pd.to_datetime(df['deadline'])

    today = datetime.now().date()
    tomorrow = today + timedelta(days=1)

    today_df = df[df['deadline'].dt.date == today]
    tomorrow_df = df[df['deadline'].dt.date == tomorrow]
    later_df = df[df['deadline'].dt.date > tomorrow]

    today_df.to_csv(os.path.join(data_dir, "today_tasks.csv"), index=False)
    tomorrow_df.to_csv(os.path.join(data_dir, "tomorrow_tasks.csv"), index=False)
    later_df.to_csv(os.path.join(data_dir, "later_tasks.csv"), index=False)

    print("✅ Split tasks into:")
    print("   📁 today_tasks.csv")
    print("   📁 tomorrow_tasks.csv")
    print("   📁 later_tasks.csv")