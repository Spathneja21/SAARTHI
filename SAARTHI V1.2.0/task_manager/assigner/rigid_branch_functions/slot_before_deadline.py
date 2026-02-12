import csv
import os
from datetime import datetime
import calendar
from pathlib import Path

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
    tasks = []
    with open(csv_file_path, 'r') as file:
        reader = csv.DictReader(file)
        for row in reader:
            tasks.append({
                'task_name': row['task_name'],
                'duration': float(row['duration']),
                'deadline': datetime.strptime(row['deadline'], '%Y-%m-%d %H:%M'),
                'priority': int(row['priority']),
                'flexibility': row['flexibility']
            })
    
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
    
    return task_available_slots


# Usage example (add this to your existing code):
def display_available_slots_for_tasks(task_available_slots):
    """Display the available slots for each task"""
    print("\n" + "=" * 80)
    print("AVAILABLE FREE SLOTS BEFORE TASK DEADLINES")
    print("=" * 80)
    
    for task_name, data in task_available_slots.items():
        task_info = data['task_info']
        available_slots = data['available_slots']
        total_time = data['total_available_time']
        
        print(f"\nTask: {task_name}")
        print(f"  Duration Needed: {task_info['duration']:.2f} hours")
        print(f"  Deadline: {task_info['deadline'].strftime('%Y-%m-%d %H:%M')}")
        print(f"  Priority: {task_info['priority']}")
        print(f"  Total Available Time: {total_time:.2f} hours")
        
        if total_time >= task_info['duration']:
            print(f"  Status: ✓ Sufficient time available")
        else:
            print(f"  Status: ✗ Insufficient time (need {task_info['duration'] - total_time:.2f} more hours)")
        
        print(f"  Available Slots ({len(available_slots)}):")
        for i, slot in enumerate(available_slots, 1):
            slot_type = "⚡ Partial" if slot['type'] == 'partial' else "✓ Complete"
            print(f"    {i}. {slot['start']} - {slot['end']} ({slot['duration']:.2f}h) [{slot_type}]")
    
    print("\n" + "=" * 80)


# Add this to your existing code after creating free_slot:

# task_slots = filter_free_slots_before_deadline()
    
#     # Display the results
# display_available_slots_for_tasks(task_slots)