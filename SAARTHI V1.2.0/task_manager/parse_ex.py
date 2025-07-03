from task_manager.insertion_package.duration import extract_duration
from task_manager.insertion_package.deadline import extract_deadline
from task_manager.insertion_package.priority import extract_priority
import pandas as pd
import os

def extract_task_name(text):
    words = text.split()
    if len(words) > 5:
        return " ".join(words[:5]).capitalize()
    return text.capitalize()

def save_task_to_csv(task_dict, filepath="D:\ACADEMICS\AI PROJECT\SAARTHI V1.2.0\task_manager\data\etasks.csv"):
    # Create directory if it doesn't exist
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    try:
        df = pd.read_csv(filepath)
    except FileNotFoundError:
        df = pd.DataFrame(columns=["task_name", "duration", "deadline", "priority"])

    df = pd.concat([df, pd.DataFrame([task_dict])], ignore_index=True)
    df.drop_duplicates(subset="task_name", keep="last", inplace=True) 
    df.to_csv(filepath, index=False)
    print(f"✅ Task saved to '{filepath}'")

# --- Parse and Save ---
def parse_task_input(text):
    return {
        "task_name": extract_task_name(text),
        "duration": extract_duration(text),
        "deadline": extract_deadline(text),
        "priority": extract_priority(text)
    }

# parse_task_input()
# save_task_to_csv(task_dict)

