import os
import pandas as pd
from datetime import datetime, timedelta

def assign(rigid_tasks):
    print("🔧 Assigning rigid tasks...")

    # Step 1️⃣: Load input files
    base_dir = os.path.dirname(os.path.dirname(__file__))
    data_dir = os.path.join(base_dir, "data")
    assigned_today_path = os.path.join(data_dir, "assigned_today.csv")
    grouped_schedule_path = os.path.join(data_dir, "grouped_schedule.csv")

    if not os.path.exists(assigned_today_path) or not os.path.exists(grouped_schedule_path):
        print("❌ Required input files not found.")
        return pd.DataFrame()

    tasks_df = pd.read_csv(assigned_today_path)
    schedule_df = pd.read_csv(grouped_schedule_path)

    # Step 2️⃣: Extract occupied blocks and generate free slots
    def parse_time(t_str):
        return datetime.strptime(t_str, "%H:%M")

    occupied = []
    for _, row in schedule_df.iterrows():
        start = parse_time(row['Start'])
        end = parse_time(row['End'])
        occupied.append((start, end))
    occupied.sort()

    free_slots = []
    current = parse_time("06:00")
    for start, end in occupied:
        if current < start:
            free_slots.append((current, start))
        current = max(current, end)
    end_of_day = parse_time("23:59")
    if current < end_of_day:
        free_slots.append((current, end_of_day))

    # Step 3️⃣: Process each rigid task and assign if possible
    rigid_df = rigid_tasks.copy()
    rigid_df["assigned_start"] = ""
    rigid_df["assigned_end"] = ""

    for i, row in rigid_df.iterrows():
        duration_hours = float(row['duration'])
        deadline = pd.to_datetime(row['deadline'])
        deadline_dt = datetime.combine(datetime.today(), deadline.time())

        assigned = False
        for j, (slot_start, slot_end) in enumerate(free_slots):
            slot_duration = (slot_end - slot_start).total_seconds() / 3600.0
            if slot_duration >= duration_hours and slot_end <= deadline_dt:
                assigned_start = slot_start
                assigned_end = slot_start + timedelta(hours=duration_hours)
                rigid_df.at[i, "assigned_start"] = assigned_start.strftime("%H:%M")
                rigid_df.at[i, "assigned_end"] = assigned_end.strftime("%H:%M")
                print(f"✅ '{row['task_name']}' assigned: {assigned_start.time()} → {assigned_end.time()}")

                # Step 4️⃣: Update free slots by splitting the used one
                new_slots = []
                for s_start, s_end in free_slots:
                    if s_start == slot_start and s_end == slot_end:
                        if assigned_start > s_start:
                            new_slots.append((s_start, assigned_start))
                        if assigned_end < s_end:
                            new_slots.append((assigned_end, s_end))
                    else:
                        new_slots.append((s_start, s_end))
                free_slots = new_slots
                assigned = True
                break

        if not assigned:
            print(f"❌ Could not assign '{row['task_name']}' — no available slot.")

    return rigid_df
