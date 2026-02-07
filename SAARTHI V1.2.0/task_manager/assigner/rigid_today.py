import numpy as np
def assign(df):
    mean_duration = np.mean(df['duration'])
    print(f"The mean duration is: {mean_duration}")
    if mean_duration>3:
        print('branch 2 (neeeche wali).')


    else:
        print('branch 1 (upar wali).')
        