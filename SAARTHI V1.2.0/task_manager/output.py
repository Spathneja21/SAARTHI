# # task_manager/main_schedule.py

# import os
# import pandas as pd
# from task_manager.schedular.expand_slots import expand_to_5_min_slots
# from task_manager.schedular.group_slots import group_slots_by_task
# from task_manager.schedular.load_data import load_and_expand  

# def run_schedule():
#     # File paths
#     base_dir = os.path.dirname(__file__)
#     data_dir = os.path.join(base_dir, "data")
#     input_csv = os.path.join(data_dir, "fixed_tasks.csv")
#     output_csv = os.path.join(data_dir, "grouped_schedule.csv")

#     # Load and expand
#     df = pd.read_csv(input_csv)
#     expanded_records = []
#     for _, row in df.iterrows():
#         expanded_records.extend(expand_to_5_min_slots(row['Day'], row['Start'], row['End'], row['Task']))
#     expanded_df = pd.DataFrame(expanded_records)

#     # Group back
#     grouped_df = group_slots_by_task(expanded_df)
#     grouped_df.to_csv(output_csv, index=False)

#     print("✅ Grouped schedule saved to:", output_csv)

#     # View specific day
#     day = input("📆 Enter the day to view (e.g. Monday): ").capitalize()
#     load_and_expand(grouped_df, day)


# task_manager/output.py

# task_manager/output.py
from task_manager.schedular.combiner import combine_csv
from task_manager.schedular.expand_slots import expand_combined_csv
from task_manager.schedular.grouped import group_expanded_schedule
from task_manager.schedular.load_data import load_and_expand

def show_day_schedule():
    combine_csv()
    expand_combined_csv()
    grouped_df = group_expanded_schedule()
    day = input("📆 Enter the day you want to view schedule for: ").capitalize()
    load_and_expand(grouped_df, day)

