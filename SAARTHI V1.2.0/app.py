import pandas as pd
import time

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


from task_manager import day_sorter
day_sorter.main()

# t0= time.time()
from task_manager import decision
decision.main()
# t1= time.time()

# print(f"The total time duration of our process is :{t1-t0:.4f} seconds")

# from task_manager import decision
# import numpy as np

# # 1. Create a list to store the time taken for each of the 5 runs
# runtimes = []

# print(f"Starting 5-iteration performance test...\n")

# for i in range(1, 6):
#     # Capture start time
#     t0 = time.time()
    
#     # Execute the process
#     decision.main()
    
#     # Capture end time
#     t1 = time.time()
    
#     # Calculate duration and append to list
#     duration = t1 - t0
#     runtimes.append(duration)
    
#     print(f"Iteration {i}: {duration:.4f} seconds")

# print(runtimes)
# # 2. Calculate the average
# average_time = np.mean(runtimes)

# print("-" * 40)
# print(f"Total Average Time: {average_time:.4f} seconds")
# print("-" * 40)
# current = get_current_time()
# variables = calculation(current)
# result = decision_and_output(variables)
# df = pd.DataFrame(result, columns=["Task", "Start", "End"])
# print(df)
