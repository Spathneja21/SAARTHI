import pandas as pd

def process_flexibility(df: pd.DataFrame) -> pd.DataFrame:
    print("🔧 Starting flexibility assignment...\n")

    if 'flexibility' not in df.columns:
        df['flexibility'] = ""

    for idx, row in df.iterrows():
        task_name = row['task_name']
        deadline = row['deadline']
        priority = row['priority']
        duration = row['duration']

        while True:
            print(f"📝 Task: {task_name} | Duration: {duration} hrs | Deadline: {deadline} | Priority: {priority}")
            user_input = input("   → Is this task 'rigid' or 'flexible'? ").strip().lower()

            if user_input in ['rigid', 'flexible']:
                # ✅ Override rigid if duration > 4 hours
                if user_input == 'rigid' and duration > 4:
                    df.at[idx, 'flexibility'] = 'semi-flexible'
                    print("   ⚠️ Duration > 4 hrs — marked as 'semi-flexible' instead of 'rigid'.\n")
                else:
                    df.at[idx, 'flexibility'] = user_input
                break
            else:
                print("   ⚠️ Please enter only 'rigid' or 'flexible'.\n")

    print("\n✅ Flexibility tagging complete.\n")
    return df
