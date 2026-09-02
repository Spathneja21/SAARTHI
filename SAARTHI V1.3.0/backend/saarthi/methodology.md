i am thinking of a methodology and i will write it in the pointers:

1. when i am scheduling the fixed tasks, we have the @fixed_tasks.json file which contains the fixed tasks and it contains the columns of the tasks such as title, start_time, end_time, and day. So , for that we should use the datetime function to make the fixed slots in the weeks and only after that we will use the schedule logic to schedule the tasks.

2. for now we are using a slot score calculator to assign the task in the slot and it has a resolution of 15 mins that means it calculates the score for each slot of 15 mins to check if we should assign the task there. 
this is getting operated from the /ml/lgbm_train.py , /ml/ml_train.py and /ml/ml_features.py.
I want to improve this, first assign the fixed tasks in the schedule from fixed_tasks.json and only after then we will try to calculate the scores and assign the tasks. (this will reduce our computation and extra load).
Further, i have got an idea to improve the computation on the free days because it will have a lot of slots which will increase our computation so we use 

if free_hours_in_a_day < 8:
    slot_min = 15 minutes
else:
    slot_min = 60 minutes

this is just an example , we can tune it further according to our need.

