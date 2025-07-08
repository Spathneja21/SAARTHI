# import pandas as pd
# import os

# def build_schedule_record(save_combined=True):
#     base_dir = os.path.dirname(os.path.dirname(__file__))  # task_manager/
#     data_dir = os.path.join(base_dir, "data")

#     files = [
#         "combined.csv",             # already merged fixed + sleep + meals
#         "updated_today.csv",
#         "updated_tomorrow.csv",
#         "updated_later.csv"
#     ]

#     schedule_parts = []

#     for fname in files:
#         fpath = os.path.join(data_dir, fname)
#         if os.path.exists(fpath):
#             try:
#                 df = pd.read_csv(fpath)
#                 schedule_parts.append(df)
#                 print(f"📦 Loaded: {fname}")
#             except Exception as e:
#                 print(f"⚠️ Could not load {fname}: {e}")

#     if not schedule_parts:
#         print("❌ No schedule components found.")
#         return pd.DataFrame()

#     full_schedule = pd.concat(schedule_parts, ignore_index=True)

#     # Optional: sort by Day and Start time
#     if "Day" in full_schedule.columns and "Start" in full_schedule.columns:
#         full_schedule = full_schedule.sort_values(by=["Day", "Start"])

#     # Save for UI/debugging
#     if save_combined:
#         output_path = os.path.join(data_dir, "schedule_full.csv")
#         full_schedule.to_csv(output_path, index=False)
#         print(f"✅ Full schedule saved to: {output_path}")

#     return full_schedule


import pandas as pd
import os

def build_schedule_record():
    base_dir = os.path.dirname(os.path.dirname(__file__))  # task_manager/
    data_dir = os.path.join(base_dir, "data")
    full_path = os.path.join(data_dir, "grouped_schedule.csv")

    if not os.path.exists(full_path):
        print("❌ full_schedule.csv not found.")
        return pd.DataFrame()

    try:
        df = pd.read_csv(full_path)
        df = df.dropna(subset=["Day", "Start", "End", "Task"])  # clean rows

        # Optional: sort by Day + Start
        df = df.sort_values(by=["Day", "Start"]).reset_index(drop=True)

        print(f"✅ Full schedule loaded with {len(df)} rows.")
        return df
    except Exception as e:
        print(f"⚠️ Error reading full_schedule.csv: {e}")
        return pd.DataFrame()
