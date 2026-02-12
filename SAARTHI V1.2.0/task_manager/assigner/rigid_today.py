import numpy as np
import os
from datetime import datetime
import csv
import calendar
from task_manager.assigner.rigid_branch_functions.slot_before_deadline import filter_free_slots_before_deadline , display_available_slots_for_tasks
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

        task_available_slots = filter_free_slots_before_deadline(free_slot,today_day_name)
        display_available_slots_for_tasks(task_available_slots)
        print('branch (1.1.1)')

        