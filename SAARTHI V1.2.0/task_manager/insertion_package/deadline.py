import parsedatetime
from datetime import datetime , timedelta

# Initialize the calendar parser
cal = parsedatetime.Calendar()

# Function to extract deadline from natural language
def extract_deadline(text):
    time_struct, parse_status = cal.parse(text)
    dt = datetime(*time_struct[:6])

    if not parse_status or dt == datetime.now().replace(second=0, microsecond=0):
        dt = datetime.now() + timedelta(days=2)
        dt = dt.replace(hour=17, minute=0)

    return dt.strftime("%Y-%m-%d %H:%M")

