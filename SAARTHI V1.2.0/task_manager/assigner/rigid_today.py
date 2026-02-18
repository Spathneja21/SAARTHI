import numpy as np
import os
from datetime import datetime
import csv
import calendar
from task_manager.assigner.rigid_branch_functions.slot_before_deadline import filter_free_slots_before_deadline , display_available_slots_for_tasks

from task_manager.calculator.score_calculation import calculate_dataframe_scores
def assign(df):
    mean_duration = np.mean(df['duration'])
    print(f"The mean duration is: {mean_duration}")
    if mean_duration>3:
        print('branch 2 (neeeche wali)(2).')


    else:
        print('branch 1 (upar wali).(1)')
        base_dir = os.path.dirname(os.path.dirname(__file__))
        data_dir = os.path.join(base_dir, "data")
        csv_file_path = os.path.join(data_dir, 'grouped_schedule.csv')

        # Create a set to store free slots
        free_slot = set()

        # Read the CSV file
        with open(csv_file_path, 'r') as file:
            reader = csv.DictReader(file)
            rows = list(reader)

        # Group tasks by day
        days_schedule = {}
        for row in rows:
            day = row['Day']
            if day not in days_schedule:
                days_schedule[day] = []
            days_schedule[day].append({
                'start': row['Start'],
                'end': row['End'],
                'task': row['Task']
            })

        # Find free slots between consecutive tasks for each day
        for day, tasks in days_schedule.items():
            # Sort tasks by start time to ensure they're in order
            tasks.sort(key=lambda x: datetime.strptime(x['start'], '%H:%M'))
            
            # Loop through consecutive tasks
            for i in range(len(tasks) - 1):
                task1_end = tasks[i]['end']
                task2_start = tasks[i + 1]['start']
                
                # Parse times
                end_time = datetime.strptime(task1_end.strip(), '%H:%M')
                start_time = datetime.strptime(task2_start.strip(), '%H:%M')
                
                # Check if there's a gap between task1 end and task2 start
                if end_time < start_time:
                    # Calculate the gap duration in hours
                    gap_duration = (start_time - end_time).total_seconds() / 3600
                    
                    # Add to free_slot set as a tuple (day, start, end, duration_in_hours)
                    free_slot.add((day, task1_end, task2_start, gap_duration))

        today = datetime.now()
        today_day_name = calendar.day_name[today.weekday()]
        
        # Display the free slots
        print("Free Time Slots:")
        print("-" * 80)
        for slot in sorted(free_slot, key=lambda x: (x[0], x[1])):
            day, start, end, duration = slot
            print(f"{day:12} | {start} - {end} | Duration: {duration:.2f} hours")

        print(f"\nTotal free slots found: {len(free_slot)}")

        # Calculate total free time
        total_free_hours = sum(slot[3] for slot in free_slot)
        print(f"Total free time: {total_free_hours:.2f} hours")

        today_free_slots = [slot for slot in free_slot if slot[0] == today_day_name]

        # Display the free slots for today
        print("Free Time Slots for Today:")
        print("-" * 80)
        for slot in sorted(today_free_slots, key=lambda x: x[1]):
            day, start, end, duration = slot
            print(f"{day:12} | {start} - {end} | Duration: {duration:.2f} hours")

        print(f"\nTotal free slots found today: {len(today_free_slots)}")
        print('branch 1.1')

        print(type(free_slot))
        task_available_slots = filter_free_slots_before_deadline(free_slot,today_day_name)

        test_now = datetime(2026, 2, 18, 14, 30)

        result_slots_and_details = display_available_slots_for_tasks(task_available_slots,test_now)

        print("Dataframe1")
        print(result_slots_and_details)

        base_dir1 = os.path.dirname(os.path.dirname(__file__))
        data_dir1 = os.path.join(base_dir1, "data")
        csv_file_path1 = os.path.join(data_dir1, 'updated_today_assign.csv')

        import pandas as pd

        # Load the full dataframe from CSV
        input_for_score = pd.read_csv(csv_file_path1)
        input_for_score_df = pd.DataFrame(input_for_score)

        # --- FILTERING STEP ---
        # This creates a new dataframe containing only 'rigid' tasks
        rigid_tasks_df = input_for_score_df[input_for_score_df['flexibility'] == 'rigid'].copy()

        # Extract the necessary columns from the filtered set
        df_subset_ADD = rigid_tasks_df[['task_name', 'adjusted_deadline_diff']]

        print("\nDataframe2 (Filtered for Rigid Tasks Only):")
        print(rigid_tasks_df)

        result_slots_and_details = pd.merge(
            result_slots_and_details, 
            df_subset_ADD, 
            on='task_name', 
            how='left'
        )

        print("\nDataframe1 UPDATED.")
        print(result_slots_and_details)

        # --- START OF CONSTRAINT CHECK ---
        
        # 1. Get the list of all tasks that were supposed to be assigned
        original_tasks = set(df_subset_ADD['task_name'].unique())
        print("original tasks:\n",original_tasks)
        
        # 2. Get the list of tasks that actually found valid slots before their deadlines
        tasks_with_valid_slots = set(result_slots_and_details['task_name'].dropna().unique())
        print('valid_slots\n',tasks_with_valid_slots)

        # 3. Check if all tasks passed constraints 1 & 2
        all_tasks_fulfilled = original_tasks.issubset(tasks_with_valid_slots)
        

        if all_tasks_fulfilled:
            print("\n✅ ALL CONSTRAINTS MET: All tasks have valid slots before deadlines.")
            
            print('branch (1.1.1)')

            print("Proceeding to Score Calculation Branch...")

            # Extract only the columns required for the scoring algorithm
            scoring_input_df = result_slots_and_details[[
                'task_name', 
                'priority', 
                'duration_needed', 
                'adjusted_deadline_diff'
            ]].copy()

            # Drop duplicates if you want to calculate one score per task 
            # (rather than one score per available slot)
            task_scores_input = scoring_input_df.drop_duplicates(subset=['task_name'])

            print("\nInput for Score Calculation:")
            print(task_scores_input)

            scores = calculate_dataframe_scores(task_scores_input)
            print(scores)
            print('branch 1.1.1.1')
            
            
            # --- Score Calculation Method ---
            # Example: result_slots_and_details['score'] = (result_slots_and_details['priority'] * 10) / result_slots_and_details['adjusted_deadline_diff']
            # return calculate_scores(result_slots_and_details)
            
        else:
            missing_tasks = original_tasks - tasks_with_valid_slots
            print(f"\n❌ CONSTRAINTS FAILED: The following tasks have no valid slots: {missing_tasks}")
            print("Diverting to Alternative Methods (Branch 1.2)...")
            
            # --- Other Methods Branch ---
            # return run_alternative_scheduling(input_for_score_df)
            
        # --- END OF CONSTRAINT CHECK ---
        