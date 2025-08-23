# task_manager/schedular/rest_handler.py

import pandas as pd
from datetime import datetime, timedelta

def insert_rest_buffers(df):
    buffer_rows = []
    fmt = "%H:%M"

    for i in range(len(df)):
        row = df.iloc[i]

        # Insert 5-min preparation before task if not directly after another task
        if i == 0 or df.iloc[i - 1]["End"] < row["Start"]:
            prep_start = (datetime.strptime(row["Start"], fmt) - timedelta(minutes=5)).strftime(fmt)
            buffer_rows.append({
                "Day": row["Day"],
                "Start": prep_start,
                "End": row["Start"],
                "Task": "Prepare for the upcoming task"
            })

        # Insert 15-min rest after task if not immediately followed by another1
        if i == len(df) - 1 or df.iloc[i]["End"] < df.iloc[i + 1]["Start"]:
            rest_start = row["End"]
            rest_end = (datetime.strptime(rest_start, fmt) + timedelta(minutes=15)).strftime(fmt)
            buffer_rows.append({
                "Day": row["Day"],
                "Start": rest_start,
                "End": rest_end,
                "Task": "Rest Time"
            })

    buffer_df = pd.DataFrame(buffer_rows)
    final_df = pd.concat([df, buffer_df], ignore_index=True)
    final_df = final_df.sort_values(by=["Day", "Start"]).reset_index(drop=True)
    return final_df
