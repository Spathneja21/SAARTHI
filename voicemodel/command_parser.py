"""
Rule-based command parser for SAARTHI voice input.
Output schema matches transformer_parser.py so the scheduler doesn't care which parser produced it.
No ML, no downloads, deterministic, instant.
"""
import re

NUM_WORDS = {
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
    "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty five": 45,
}
DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
DATE_WORDS = ["day after tomorrow", "tomorrow", "today", "tonight"] + DAYS


def _empty(raw):
    return {"intent": "unknown", "task_name": None, "date": None, "time": None,
            "deadline": None, "duration_minutes": None, "priority": None,
            "rigid": None, "raw_text": raw}


def normalize(text):
    t = text.strip().lower()
    t = re.sub(r"\b([ap])\.\s?m\.?", r"\1m", t)                       # "6 p.m." -> "6pm"
    t = re.sub(r"\b(\d{1,2})[. ](\d{2})\s?(am|pm)\b", r"\1:\2 \3", t)  # "11.20 am" / "11 20 am" -> "11:20 am"
    t = re.sub(r"[.,!?]+(\s|$)", r"\1", t)                             # strip punctuation Whisper adds
    return re.sub(r"\s+", " ", t).strip()


def extract_time(t):
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s?(am|pm)\b", t)
    if m:
        h, mins, ap = int(m.group(1)), m.group(2) or "00", m.group(3).upper()
        return f"{h}:{mins} {ap}" if mins != "00" else f"{h} {ap}"
    m = re.search(r"\b(?:at\s+)?(\d{1,2}):(\d{2})\b", t)   # 24h "18:30"
    return f"{int(m.group(1))}:{m.group(2)}" if m else None


def extract_date(t):
    for w in DATE_WORDS:
        if re.search(rf"\b{w}\b", t):
            return w
    return None


def extract_deadline(t):
    m = re.search(r"\b(?:before|by|due|until)\s+(?:this\s+|next\s+)?(" + "|".join(DATE_WORDS) + r")\b", t)
    return m.group(1) if m else None


def extract_duration(t):
    total, found = 0, False
    for m in re.finditer(r"\b(\d+(?:\.\d+)?|" + "|".join(NUM_WORDS) + r")\s*(hours?|hrs?|minutes?|mins?)\b", t):
        n = float(m.group(1)) if m.group(1)[0].isdigit() else NUM_WORDS[m.group(1)]
        total += n * (60 if m.group(2).startswith("h") else 1)
        found = True
    if re.search(r"\bhalf an hour\b", t):
        total, found = total + 30, True
    m = re.search(r"\b(\d+|one|two|three)\s+and a half hours?\b", t)
    if m:
        n = int(m.group(1)) if m.group(1).isdigit() else NUM_WORDS[m.group(1)]
        total, found = n * 60 + 30, True
    return int(total) if found else None


def extract_priority(t):
    m = re.search(r"\b(high|low|medium)\s+priority\b", t) or re.search(r"\bpriority\s+(high|low|medium)\b", t)
    if m:
        return m.group(1)
    if re.search(r"\b(urgent|important|asap|critical)\b", t):
        return "high"
    return None


def extract_rigid(t):
    if re.search(r"\b(fixed|cannot be moved|can't be moved|must be at|rigid)\b", t):
        return True
    if re.search(r"\b(flexible|anytime|any time)\b", t):
        return False
    return None


def clean_task_name(s):
    # cut at first time/date/duration/priority phrase
    cut = (r"\b(?:on\s+)?(?:" + "|".join(DATE_WORDS) + r")\b|\bat \d|\b\d{1,2}(?::\d{2})?\s?(?:am|pm)\b"
           r"|\b(?:before|by|due|until)\b|\bit (?:will|should|would) take\b|\bfor (?:about |around )?\d"
           r"|\b(?:high|low|medium) priority\b|\bwith (?:high|low|medium)\b")
    s = re.split(cut, s)[0]
    s = re.sub(r"^(?:the|my|a|an)\s+", "", s)
    s = re.sub(r"\s+task$", "", s)
    s = re.sub(r"\b(?:and|please|on|at|for|in)$", "", s.strip()).strip()
    return s or None


def parse_command(text):
    raw = text
    t = normalize(text)
    out = _empty(raw)
    if not t:
        return out

    if re.search(r"\b(show|list|what are|what's|display)\b.*\b(tasks?|schedule|plan)\b", t):
        out["intent"] = "show_tasks"; return out

    m = re.search(r"\b(?:delete|remove|cancel)\s+(?:the |my )?(?:task\s+)?(?:called |named )?(.+)", t)
    if m:
        out.update(intent="delete_task", task_name=clean_task_name(m.group(1))); return out

    m = re.search(r"\b(?:mark|complete|finish(?:ed)?|done with)\s+(?:the |my )?(?:task\s+)?(?:called |named )?(.+?)(?:\s+as (?:done|complete|completed))?$", t)
    if m and re.search(r"\b(mark|completed?|done)\b", t):
        out.update(intent="complete_task", task_name=clean_task_name(m.group(1))); return out

    m = re.search(r"\b(?:move|reschedule|shift|postpone)\s+(?:the |my )?(.+?)(?:\s+(?:from|to|until)\b.*)?$", t)
    if m and re.search(r"\b(move|reschedule|shift|postpone)\b", t):
        out.update(intent="reschedule_task", task_name=clean_task_name(m.group(1)),
                   date=extract_date(t.split(" to ", 1)[-1]) if " to " in t else extract_date(t),
                   time=extract_time(t.split(" to ", 1)[-1]) if " to " in t else extract_time(t)); return out

    patterns = [
        r"(?:add|create|make|schedule|set up)\s+(?:a |an |the )?(?:new )?task\s+(?:called |named |to )?(.+)",
        r"(?:add|create|schedule)\s+(?:a |an |my )?(.+)",
        r"remind me to\s+(.+)",
        r"i (?:need|have|want|should|must) to\s+(.+)",
        r"i have (?:a |an )?(.+)",
    ]
    for p in patterns:
        m = re.search(p, t)
        if m:
            out.update(intent="add_task", task_name=clean_task_name(m.group(1)),
                       date=extract_date(t), time=extract_time(t), deadline=extract_deadline(t),
                       duration_minutes=extract_duration(t), priority=extract_priority(t),
                       rigid=extract_rigid(t))
            if out["deadline"] and out["date"] == out["deadline"]:
                out["date"] = None      # "before friday" is a deadline, not a start date
            return out
    return out
