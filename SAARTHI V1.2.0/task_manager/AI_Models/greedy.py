# import pandas as pd
# from pathlib import Path
# import calendar
# from datetime import datetime, timedelta

# # 1. Get the current date
# today = datetime.now()

# # 2. Get the day name (e.g., 'Monday')
# today_day_name = calendar.day_name[today.weekday()]
# current_file = Path(__file__)
# data_dir = current_file.parent.parent / "data"
# print('datadir =', data_dir)
# csv_file_path = data_dir / 'grouped_schedule.csv'
# output_path = data_dir / 'final_assigned_schedule.csv'
# temp_schedule_path = data_dir / 'temp_schedule.csv'


# def greedy_assigner(rigid_data, today_free_slots):
#     print("Starting greedy assignment...\n")
    
#     # Step 1: Load the free slots
#     print("Step 1: Loading free slots")
#     free_slots_df = pd.DataFrame(today_free_slots, columns=['Day', 'Start', 'End', 'Time_slot'])
#     print(free_slots_df)
    
#     # Step 2: Copy grouped_schedule.csv to temporary file
#     print("\nStep 2: Creating temporary schedule file")
#     original_schedule = pd.read_csv(csv_file_path)
#     temp_schedule = original_schedule.copy()
#     temp_schedule.to_csv(temp_schedule_path, index=False)
#     print(f"Temporary schedule created at {temp_schedule_path}")
    
#     # Step 3: Loop through rigid tasks sorted by adjusted_deadline_diff
#     print("\nStep 3: Assigning tasks from rigid_data")
#     print(f"Total tasks to assign: {len(rigid_data)}")
    
#     for idx, task in rigid_data.iterrows():
#         task_name = task['task_name']
#         task_duration = task['duration_needed']
#         adjusted_deadline_diff = task['adjusted_deadline_diff']
        
#         print(f"\n--- Assigning Task {idx + 1}: {task_name} ---")
#         print(f"Duration: {task_duration} hours, Deadline Diff: {adjusted_deadline_diff}")
        
#         # Step 3a: Load the temporary schedule
#         temp_schedule = pd.read_csv(temp_schedule_path)
        
#         # Step 3b: Get available free time slots for today
#         today_slots = free_slots_df[free_slots_df['Day'] == today_day_name].copy()
        
#         if today_slots.empty:
#             print(f"No free slots available for {task_name}")
#             continue
        
#         # Step 3c: Find the best slot that fits the task duration
#         assigned = False
#         for slot_idx, slot in today_slots.iterrows():
#             start_time = pd.to_datetime(slot['Start'], format='%H:%M')
#             end_time = pd.to_datetime(slot['End'], format='%H:%M')
#             slot_duration = (end_time - start_time).total_seconds() / 3600
            
#             if slot_duration >= task_duration:
#                 # Step 3d: Add task to temporary schedule
#                 new_end_time = start_time + timedelta(hours=task_duration)
                
#                 new_entry = pd.DataFrame({
#                     'Day': [today_day_name],
#                     'Start': [start_time.strftime('%H:%M')],
#                     'End': [new_end_time.strftime('%H:%M')],
#                     'Task': [task_name]
#                 })
                
#                 temp_schedule = pd.concat([temp_schedule, new_entry], ignore_index=True)
#                 print(f"✓ Assigned {task_name} from {start_time.strftime('%H:%M')} to {new_end_time.strftime('%H:%M')}")
                
#                 # Step 3e: Update the temporary CSV
#                 temp_schedule.to_csv(temp_schedule_path, index=False)
                
#                 # Update free slots (remove or adjust the used slot)
#                 remaining_duration = slot_duration - task_duration
#                 if remaining_duration > 0:
#                     free_slots_df.loc[slot_idx, 'Start'] = new_end_time.strftime('%H:%M')
#                 else:
#                     free_slots_df = free_slots_df.drop(slot_idx)
                
#                 assigned = True
#                 break
        
#         if not assigned:
#             print(f"✗ Could not find suitable slot for {task_name}")
    
#     # Final: Save the completed schedule
#     temp_schedule['Start'] = pd.to_datetime(temp_schedule['Start'], format='%H:%M')
#     temp_schedule = temp_schedule.sort_values(by='Start').reset_index(drop=True)
#     temp_schedule['Start'] = temp_schedule['Start'].dt.strftime('%H:%M')
    
#     temp_schedule.to_csv(output_path, index=False)
#     print(f"\n✓ Final schedule saved to {output_path}")
#     print(temp_schedule[temp_schedule['Day']==today_day_name])
    
#     return temp_schedule


import pandas as pd
from pathlib import Path
import calendar
from datetime import datetime, timedelta

# 1. Get the current date
today = datetime.now()

# 2. Get the day name (e.g., 'Monday')
today_day_name = calendar.day_name[today.weekday()]
current_file = Path(__file__)
data_dir = current_file.parent.parent / "data"
print('datadir =', data_dir)
csv_file_path = data_dir / 'grouped_schedule.csv'
output_path = data_dir / 'final_assigned_schedule.csv'
temp_schedule_path = data_dir / 'temp_schedule.csv'


def greedy_assigner(rigid_data, today_free_slots):
    print("Starting greedy assignment...\n")
    
    # Step 1: Load the free slots
    print("Step 1: Loading free slots")
    free_slots_df = pd.DataFrame(today_free_slots, columns=['Day', 'Start', 'End', 'Time_slot'])
    print(free_slots_df)
    
    # Step 2: Copy grouped_schedule.csv to temporary file
    print("\nStep 2: Creating temporary schedule file")
    original_schedule = pd.read_csv(csv_file_path)
    temp_schedule = original_schedule.copy()
    temp_schedule.to_csv(temp_schedule_path, index=False)
    print(f"Temporary schedule created at {temp_schedule_path}")
    
    # Load the full task data with deadlines
    rigid_tasks_csv_path = data_dir / 'updated_today_assign.csv'
    all_tasks_data = pd.read_csv(rigid_tasks_csv_path)
    
    # Step 3: Loop through rigid tasks sorted by adjusted_deadline_diff
    print("\nStep 3: Assigning tasks from rigid_data")
    print(f"Total tasks to assign: {len(rigid_data)}")
    
    for idx, task in rigid_data.iterrows():
        task_name = task['task_name']
        task_duration = task['duration_needed']
        adjusted_deadline_diff = task['adjusted_deadline_diff']
        
        print(f"\n--- Assigning Task {idx + 1}: {task_name} ---")
        print(f"Duration: {task_duration} hours, Deadline Diff: {adjusted_deadline_diff}")
        
        # Step 3a: Load the temporary schedule
        temp_schedule = pd.read_csv(temp_schedule_path)
        
        # Step 3b: Get available free time slots for today
        today_slots = free_slots_df[free_slots_df['Day'] == today_day_name].copy()
        
        if today_slots.empty:
            print(f"No free slots available for {task_name}")
            continue
        
        # Step 3c: Find the best slot that fits the task duration
        assigned = False
        for slot_idx, slot in today_slots.iterrows():
            start_time = pd.to_datetime(slot['Start'], format='%H:%M')
            end_time = pd.to_datetime(slot['End'], format='%H:%M')
            slot_duration = (end_time - start_time).total_seconds() / 3600
            
            if slot_duration >= task_duration:
                # NEW: Step 3d - Check for deadline conflicts
                new_end_time = start_time + timedelta(hours=task_duration)
                
                # Get all tasks scheduled for today from temp_schedule
                today_schedule = temp_schedule[temp_schedule['Day'] == today_day_name].copy()
                
                # Check for tasks with deadlines that fall within the proposed assignment time
                conflicting_tasks = []
                
                for _, scheduled_task in today_schedule.iterrows():
                    scheduled_task_name = scheduled_task['Task']
                    
                    # Get deadline for this scheduled task
                    task_info = all_tasks_data[all_tasks_data['task_name'] == scheduled_task_name]
                    
                    if not task_info.empty:
                        deadline_diff = task_info.iloc[0]['adjusted_deadline_diff']
                        
                        # Calculate deadline time
                        deadline_time = datetime.now() + timedelta(hours=deadline_diff)
                        deadline_time_only = deadline_time.time()
                        
                        # Check if deadline falls within the proposed task slot
                        proposed_start = start_time.time()
                        proposed_end = new_end_time.time()
                        
                        if proposed_start <= deadline_time_only <= proposed_end:
                            conflicting_tasks.append({
                                'name': scheduled_task_name,
                                'deadline': deadline_time.strftime('%H:%M'),
                                'deadline_diff': deadline_diff
                            })
                
                # If conflicts found, ask user
                if conflicting_tasks:
                    print(f"\n⚠️  WARNING: The following tasks have deadlines during the proposed slot:")
                    print(f"   Proposed slot: {start_time.strftime('%H:%M')} to {new_end_time.strftime('%H:%M')}")
                    
                    for conflict in conflicting_tasks:
                        print(f"   - {conflict['name']} (Deadline: {conflict['deadline']}, {conflict['deadline_diff']:.2f} hours from now)")
                    
                    # Ask user for each conflicting task
                    all_completed = True
                    for conflict in conflicting_tasks:
                        while True:
                            user_input = input(f"\n   Has '{conflict['name']}' been completed? (yes/no): ").strip().lower()
                            if user_input in ['yes', 'y']:
                                print(f"   ✓ Marked {conflict['name']} as completed")
                                break
                            elif user_input in ['no', 'n']:
                                print(f"   ✗ {conflict['name']} is not completed")
                                all_completed = False
                                break
                            else:
                                print("   Invalid input. Please enter 'yes' or 'no'")
                    
                    # If any task is not completed, skip this slot
                    if not all_completed:
                        print(f"\n⚠️  Skipping this slot due to incomplete conflicting tasks")
                        continue
                    else:
                        print(f"\n✓ All conflicting tasks completed. Proceeding with assignment.")
                
                # Step 3e: Add task to temporary schedule
                new_entry = pd.DataFrame({
                    'Day': [today_day_name],
                    'Start': [start_time.strftime('%H:%M')],
                    'End': [new_end_time.strftime('%H:%M')],
                    'Task': [task_name]
                })
                
                temp_schedule = pd.concat([temp_schedule, new_entry], ignore_index=True)
                print(f"✓ Assigned {task_name} from {start_time.strftime('%H:%M')} to {new_end_time.strftime('%H:%M')}")
                
                # Step 3f: Update the temporary CSV
                temp_schedule.to_csv(temp_schedule_path, index=False)
                
                # Update free slots (remove or adjust the used slot)
                remaining_duration = slot_duration - task_duration
                if remaining_duration > 0:
                    free_slots_df.loc[slot_idx, 'Start'] = new_end_time.strftime('%H:%M')
                    free_slots_df.loc[slot_idx, 'Time_slot'] = remaining_duration
                else:
                    free_slots_df = free_slots_df.drop(slot_idx)
                
                assigned = True
                break
        
        if not assigned:
            print(f"✗ Could not find suitable slot for {task_name}")
    
    # Final: Save the completed schedule
    temp_schedule['Start'] = pd.to_datetime(temp_schedule['Start'], format='%H:%M')
    temp_schedule = temp_schedule.sort_values(by='Start').reset_index(drop=True)
    temp_schedule['Start'] = temp_schedule['Start'].dt.strftime('%H:%M')
    
    temp_schedule.to_csv(output_path, index=False)
    print(f"\n✓ Final schedule saved to {output_path}")
    print(temp_schedule[temp_schedule['Day']==today_day_name])
    
    return temp_schedule