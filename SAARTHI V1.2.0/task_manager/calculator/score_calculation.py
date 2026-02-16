import pandas as pd

def normalize_deadline(hours, min_h=1, max_h=16):
    """Normalizes deadline. Shorter deadlines get HIGHER scores."""
    # Ensure hours stay within bounds for normalization
    clamped_hours = max(min_h, min(max_h, hours))
    normalized = 1 + ((max_h - clamped_hours) * (5 - 1) / (max_h - min_h))
    return round(normalized, 2)

def normalize_duration(hours, min_h=0.5, max_h=4.5):
    """Normalizes duration. Shorter tasks get HIGHER scores (Quick Wins)."""
    clamped_hours = max(min_h, min(max_h, hours))
    normalized = 1 + ((max_h - clamped_hours) * (5 - 1) / (max_h - min_h))
    return round(normalized, 2)

def calculate_dataframe_scores(df):
    """
    Takes the merged Dataframe1 and calculates scores for every row.
    """
    # 1. Apply normalization to the columns
    df['norm_deadline'] = df['adjusted_deadline_diff'].apply(normalize_deadline)
    df['norm_duration'] = df['duration_needed'].apply(normalize_duration)
    
    # 2. Calculate Final Score (Sum of Priority, Norm Deadline, and Norm Duration)
    # Using the logic from your provided code: (priority + norm_deadline + norm_duration)
    df['final_score'] = df['priority'] + df['norm_deadline'] + df['norm_duration']
    
    # 3. Sort by final score descending to see highest priority tasks first
    df = df.sort_values(by='final_score', ascending=False).reset_index(drop=True)
    
    return df

# --- Integration Step ---
# Assuming 'result_slots_and_details' is your Dataframe1 after the merge
# final_scored_df = calculate_dataframe_scores(result_slots_and_details)

# print("\nFINAL TASK SCORES:")
# print(final_scored_df[['task_name', 'priority', 'norm_deadline', 'norm_duration', 'final_score']])