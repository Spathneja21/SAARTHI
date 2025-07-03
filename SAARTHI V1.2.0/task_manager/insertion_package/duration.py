import re
def extract_duration(text):
    text = text.lower()

    # Match hours like "2 hours", "1.5hr", etc.
    hour_match = re.search(r"(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours)", text)
    if hour_match:
        return float(hour_match.group(1))

    # Match minutes and convert to hours
    min_match = re.search(r"(\d+)\s*(m|min|mins|minutes)", text)
    if min_match:
        minutes = int(min_match.group(1))
        return round(minutes / 60, 2)

    return 0