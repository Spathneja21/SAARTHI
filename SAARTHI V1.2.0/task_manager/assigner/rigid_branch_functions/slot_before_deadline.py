import csv
import os
from datetime import datetime
import calendar
from pathlib import Path
import pandas as pd

def filter_free_slots_before_deadline(free_slot, today_day_name):
    """
    Filter free time slots that are available before the deadlines of tasks.
    Can use complete slots or split them if needed.
    
    Args:
        free_slot: Set of tuples (day, start_time, end_time, duration_in_hours)
        today_day_name: Name of today (e.g., 'Wednesday')
    
    Returns:
        Dictionary mapping task_name to list of available slots before its deadline
    """
    # Get the base directory and construct path to updated_today.csv
    # base_dir = (os.path.dirname(__file__))
    # data_dir = os.path.join(base_dir, "data")
    # csv_file_path = os.path.join(data_dir, 'updated_today_assign.csv')
    
    current_file = Path(__file__)
    data_dir = current_file.parent.parent.parent / "data"
    print('datadir =',data_dir)
    csv_file_path = data_dir / 'updated_today_assign.csv'
    print(f"Looking for file at: {csv_file_path}")
    # Read tasks from updated_today.csv
    df = pd.read_csv(csv_file_path)
    
    df = df[df['flexibility']=='rigid']
    print('our file is this ---->\n',df.head)

    tasks = []
    for _, row in df.iterrows():
        # if task['flexibility']=='rigid':
        tasks.append({
            'task_name': row['task_name'],
            'duration': float(row['duration']),
            'deadline': datetime.strptime(row['deadline'], '%Y-%m-%d %H:%M'),
            'priority': int(row['priority']),
            'flexibility': row['flexibility']
        })
    
    print("tasks",tasks)
    print("type of out tasks-->",type(tasks))
    # Get today's date
    today = datetime.now()
    
    # Dictionary to store available slots for each task
    task_available_slots = {}
    
    # Filter free slots for today only
    today_free_slots = [slot for slot in free_slot if slot[0] == today_day_name]
    
    # For each task, find all available free slots before its deadline
    for task in tasks:
        task_name = task['task_name']
        deadline = task['deadline']
        task_duration = task['duration']
        
        available_slots = []
        
        # Check each free slot
        for slot in today_free_slots:
            day, start_str, end_str, duration = slot
            
            # Combine today's date with the slot time
            slot_start = datetime.combine(today.date(), datetime.strptime(start_str.strip(), '%H:%M').time())
            slot_end = datetime.combine(today.date(), datetime.strptime(end_str.strip(), '%H:%M').time())
            
            # Check if the slot ends before or at the deadline
            if slot_end <= deadline:
                # Complete slot is available
                available_slots.append({
                    'day': day,
                    'start': start_str,
                    'end': end_str,
                    'duration': duration,
                    'type': 'complete'
                })
            elif slot_start < deadline < slot_end:
                # Partial slot available - split it
                # Only the portion from start to deadline is available
                partial_duration = (deadline - slot_start).total_seconds() / 3600
                deadline_time_str = deadline.strftime('%H:%M')
                
                available_slots.append({
                    'day': day,
                    'start': start_str,
                    'end': deadline_time_str,
                    'duration': partial_duration,
                    'type': 'partial'
                })
        
        task_available_slots[task_name] = {
            'task_info': task,
            'available_slots': available_slots,
            'total_available_time': sum(slot['duration'] for slot in available_slots)
        }
    
    print("type of our file---->", type(task_available_slots))
    return task_available_slots


def display_available_slots_for_tasks(task_available_slots, current_time):
    """
    1. Prints the formatted summary to the terminal.
    2. Returns a Pandas DataFrame for scoring/calculations.
    """
    rows = []
    
    print("\n" + "=" * 80)
    print(f"AVAILABLE FREE SLOTS (Current Time: {current_time.strftime('%Y-%m-%d %H:%M')})")
    print("=" * 80)
    
    for task_name, data in task_available_slots.items():
        task_info = data['task_info']
        available_slots = data['available_slots']
        task_date = task_info['deadline'].date()
        
        valid_future_slots = []
        for slot in available_slots:
            # Convert strings to datetimes if necessary
            if isinstance(slot['start'], str):
                s_time = datetime.strptime(slot['start'], "%H:%M").time()
                e_time = datetime.strptime(slot['end'], "%H:%M").time()
                slot_start_dt = datetime.combine(task_date, s_time)
                slot_end_dt = datetime.combine(task_date, e_time)
            else:
                slot_start_dt = slot['start']
                slot_end_dt = slot['end']

            # Filter logic
            if slot_end_dt > current_time:
                effective_start = max(slot_start_dt, current_time)
                duration = round(((slot_end_dt - effective_start).total_seconds() / 3600),2)
                
                if duration >= task_info['duration']:
                    slot_data = {
                        'task_name': task_name,
                        'priority': task_info['priority'],
                        'duration_needed': task_info['duration'],
                        'deadline': task_info['deadline'],
                        'slot_start': effective_start,
                        'slot_end': slot_end_dt,
                        'slot_duration': duration,
                        'slot_type': "⚡ Partial" if slot['type'] == 'partial' else "✓ Complete"
                    }
                    valid_future_slots.append(slot_data)
                    rows.append(slot_data)

        # --- TERMINAL PRINTING LOGIC ---
        total_time = sum(s['slot_duration'] for s in valid_future_slots)
        
        print(f"\nTask: {task_name}")
        print(f"  Duration Needed: {task_info['duration']:.2f} hours")
        print(f"  Deadline: {task_info['deadline'].strftime('%Y-%m-%d %H:%M')}")
        print(f"  Priority: {task_info['priority']}")
        print(f"  Total Future Time: {total_time:.2f} hours")
        
        if total_time >= task_info['duration']:
            print(f"  Status: ✓ Sufficient time available")
        else:
            print(f"  Status: ✗ Insufficient time (need {task_info['duration'] - total_time:.2f} more hours)")

        print(f"  Available Slots ({len(valid_future_slots)}):")
        for i, s in enumerate(valid_future_slots, 1):
            print(f"    {i}. {s['slot_start'].strftime('%H:%M')} - {s['slot_end'].strftime('%H:%M')} ({s['slot_duration']:.2f}h) [{s['slot_type']}]")
    
    print("\n" + "=" * 80)
    
    # Return the DataFrame for your scoring logic
    return pd.DataFrame(rows)

# --- EXAMPLE USAGE ---
# test_time = datetime(2026, 2, 16, 14, 30)
# df = display_and_get_task_slots(task_available_slots, test_time)


# Add this to your existing code after creating free_slot:

# task_slots = filter_free_slots_before_deadline()
    
#     # Display the results
# display_available_slots_for_tasks(task_slots)