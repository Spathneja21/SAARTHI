import spacy
import os
from task_manager.parse_ex import parse_task_input , save_task_to_csv
nlp = spacy.load("en_core_web_sm")
csv_path = os.path.join(os.path.dirname(__file__), "data", "etasks.csv")

def insert_task():
    user_input = input("📝 Enter task details:\n> ")
    task_data = parse_task_input(user_input)

    if task_data:  # ensure it's not empty
        save_task_to_csv(task_data, filepath=csv_path)
    else:
        print("⚠️ Failed to extract task data.")

insert_task()

