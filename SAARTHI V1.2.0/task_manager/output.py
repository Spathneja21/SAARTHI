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