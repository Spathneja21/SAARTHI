# import pandas as pd

# from task_manager.command import get_the_command
# from task_manager.insert import insert_task
# from task_manager.delete import delete_task
# from task_manager.current import get_current_time
# from task_manager.calculator import calculation
# from task_manager.decision import decision_and_output
# from task_manager.output import show_day_schedule

# show_day_schedule()

# app.py
# from task_manager.output import show_day_schedule

# if __name__ == "__main__":
#     show_day_schedule()

# command = get_the_command()

# if command == "insert" or command == "add":
#     insert_task()
    
# if command == "delete" or command == "remove":
#     delete_task()
#     pass


# from task_manager import day_sorter
# day_sorter.main()

from task_manager import decision
decision.main()


# current = get_current_time()
# variables = calculation(current)
# result = decision_and_output(variables)
# df = pd.DataFrame(result, columns=["Task", "Start", "End"])
# print(df)

