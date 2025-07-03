import re
def extract_priority(text):
    text = text.lower()

    # Rule-based phrases
    if "high priority" in text or "urgent" in text or "immediate" in text:
        return 5
    elif "medium priority" in text:
        return 3
    elif "low priority" in text:
        return 1

    # Regex fallback for numeric value
    match = re.search(r"priority[:=]?\s*(\d)", text)
    if match:
        return int(match.group(1))

    # Default fallback priority
    return 3