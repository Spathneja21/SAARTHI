import pandas as pd
import numpy as np
from datetime import datetime
# Sample data
# data = {
#     "task_name": [
#         "Write AI assignment", "Study ML notes", "Prepare for Robotics lab",
#         "Edit portfolio site", "Sketch EDC poster", "Complete Design Society draft",
#         "Watch AI lecture", "Submit evolution paper", "Prepare Convo AI quiz",
#         "Submit evolution paper ||", "Cal mentor and share report"
#     ],
#     "duration": [2.5, 5.5, 2.0, 1.0, 4.5, 2.0, 1.0, 1.0, 1.5, 3.0, 0.5],
#     "deadline": [
#         "2025-08-05 18:00", "2025-08-06 22:00", "2025-08-05 20:00",
#         "2025-08-06 22:00", "2025-08-05 19:00", "2025-08-07 20:00",
#         "2025-08-06 23:30", "2025-08-05 22:00", "2025-08-07 20:00",
#         "2025-08-07 22:00", "2025-08-06 19:00"
#     ],
#     "priority": [4, 3, 5, 2, 3, 4, 2, 5, 3, 4, 1]
# }

data = pd.read_csv("SAARTHI V1.2.0/task_manager/data/today_tasks.csv")

df = pd.DataFrame(data)
df["deadline"] = pd.to_datetime(df["deadline"])

# Calculate Adjusted Deadline Difference (ADD) in hours
now = pd.Timestamp(datetime(2025, 8, 5, 15, 0))  # Example current time
df["ADD_hours"] = (df["deadline"] - now).dt.total_seconds() / 3600

# Normalize the columns
df["duration_norm"] = (df["duration"] - df["duration"].min()) / (df["duration"].max() - df["duration"].min())
df["priority_norm"] = (df["priority"] - df["priority"].min()) / (df["priority"].max() - df["priority"].min())
df["add_norm"] = (df["ADD_hours"] - df["ADD_hours"].min()) / (df["ADD_hours"].max() - df["ADD_hours"].min())

# Assign Z-scores based on variance (dynamic weighting)
z_duration = df["duration_norm"].std()
z_priority = df["priority_norm"].std()
z_add = df["add_norm"].std()

z_total = z_duration + z_priority + z_add
w_duration = z_duration / z_total
w_priority = z_priority / z_total
w_add = z_add / z_total

# Calculate weight
df["weight"] = (
    df["duration_norm"] * w_duration +
    df["priority_norm"] * w_priority +
    df["add_norm"] * w_add
)

print(df)

# import caas_jupyter_tools as cj
# cj.display_dataframe_to_user(name="Weighted Task Data", dataframe=df[["task_name", "duration", "priority", "ADD_hours", "weight"]])
