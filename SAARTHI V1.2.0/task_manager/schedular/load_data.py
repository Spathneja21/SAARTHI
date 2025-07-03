def load_and_expand(schedule_df, day):
    filtered = schedule_df[schedule_df["Day"] == day]
    if filtered.empty:
        print(f"❌ No tasks found for {day}")
    else:
        print(f"\n📅 Schedule for {day}")
        print(filtered.to_string(index=False))

