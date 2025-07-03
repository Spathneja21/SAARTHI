from datetime import datetime

# Get current local date and time
now = datetime.now()

# Separate parts
current_date = now.strftime("%Y-%m-%d")     # e.g., "2025-06-14"
current_time = now.strftime("%H:%M")        # e.g., "16:45"
current_day = now.strftime("%A")            # e.g., "Saturday"

# Full print
print("📅 Date:", current_date)
print("⏰ Time:", current_time)
print("📆 Day of Week:", current_day)