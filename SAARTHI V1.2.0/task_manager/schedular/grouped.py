# import pandas as pd
# from datetime import datetime
# import os
# from .rest_handler import insert_rest_buffers

# def group_expanded_schedule():
#     base_dir = os.path.dirname(__file__)
#     data_dir = os.path.join(base_dir, "..", "data")
#     expanded_path = os.path.join(data_dir, "expanded.csv")

#     df = pd.read_csv(expanded_path)
#     df["Start_dt"] = pd.to_datetime(df["Start"], format="%H:%M")
#     df["End_dt"] = pd.to_datetime(df["End"], format="%H:%M")

#     df = df.sort_values(by=["Day", "Start_dt"]).reset_index(drop=True)

#     group_ids = [0]
#     for i in range(1, len(df)):
#         same_day = df.loc[i, "Day"] == df.loc[i - 1, "Day"]
#         same_task = df.loc[i, "Task"] == df.loc[i - 1, "Task"]
#         continuous = df.loc[i, "Start_dt"] == df.loc[i - 1, "End_dt"]
#         if same_day and same_task and continuous:
#             group_ids.append(group_ids[-1])
#         else:
#             group_ids.append(group_ids[-1] + 1)

#     df["Group"] = group_ids

#     grouped = df.groupby(["Day", "Group", "Task"]).agg(
#         Start=("Start_dt", "min"),
#         End=("End_dt", "max")
#     ).reset_index()

#     grouped["Start"] = grouped["Start"].dt.strftime("%H:%M")
#     grouped["End"] = grouped["End"].dt.strftime("%H:%M")

#     final_df = grouped[["Day", "Start", "End", "Task"]]

#     # Day ordering
#     day_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
#     final_df["Day"] = pd.Categorical(final_df["Day"], categories=day_order, ordered=True)
#     final_df = final_df.sort_values(by=["Day", "Start"])

#     output_path = os.path.join(data_dir, "grouped_schedule.csv")
#     final_df.to_csv(output_path, index=False)
#     print(f"✅ Grouped schedule saved to '{output_path}'")

#     return final_df


# task_manager/schedular/grouped.py

import pandas as pd
from datetime import datetime
import os
from .rest_handler import insert_rest_buffers  # <- Rest buffer logic

def group_expanded_schedule():
    base_dir = os.path.dirname(__file__)
    data_dir = os.path.join(base_dir, "..", "data")
    expanded_path = os.path.join(data_dir, "expanded.csv")

    df = pd.read_csv(expanded_path)
    df["Start_dt"] = pd.to_datetime(df["Start"], format="%H:%M")
    df["End_dt"] = pd.to_datetime(df["End"], format="%H:%M")

    df = df.sort_values(by=["Day", "Start_dt"]).reset_index(drop=True)

    # ----- Group continuous same tasks -----
    group_ids = [0]
    for i in range(1, len(df)):
        same_day = df.loc[i, "Day"] == df.loc[i - 1, "Day"]
        same_task = df.loc[i, "Task"] == df.loc[i - 1, "Task"]
        continuous = df.loc[i, "Start_dt"] == df.loc[i - 1, "End_dt"]
        if same_day and same_task and continuous:
            group_ids.append(group_ids[-1])
        else:
            group_ids.append(group_ids[-1] + 1)

    df["Group"] = group_ids

    grouped = df.groupby(["Day", "Group", "Task"]).agg(
        Start=("Start_dt", "min"),
        End=("End_dt", "max")
    ).reset_index()

    grouped["Start"] = grouped["Start"].dt.strftime("%H:%M")
    grouped["End"] = grouped["End"].dt.strftime("%H:%M")

    final_df = grouped[["Day", "Start", "End", "Task"]]

    # 📅 Ensure proper day order
    day_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    final_df["Day"] = pd.Categorical(final_df["Day"], categories=day_order, ordered=True)
    final_df = final_df.sort_values(by=["Day", "Start"]).reset_index(drop=True)

    # 🧘☕ Insert Rest + Prepare Blocks
    final_df = insert_rest_buffers(final_df)

    # 💾 Save Final Schedule
    output_path = os.path.join(data_dir, "grouped_schedule.csv")
    final_df.to_csv(output_path, index=False)
    print(f"✅ Grouped schedule with rest saved to '{output_path}'")

    return final_df
