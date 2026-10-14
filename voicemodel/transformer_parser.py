import json
import re
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
from command_parser import (
    normalize,
    extract_date,
    extract_time,
    extract_deadline,
    extract_duration,
    extract_priority,
    extract_rigid,
    parse_command,
)

# -----------------------------------------
# LOAD MODEL
# -----------------------------------------

MODEL_NAME = "google/flan-t5-base"

print("Loading Transformer parser...")

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)
model.eval()

print("Transformer parser loaded successfully!")

FIELDS = [
    "intent",
    "task_name",
    "date",
    "time",
    "deadline",
    "duration_minutes",
    "priority",
    "rigid",
    "raw_text",
]

VALID_INTENTS = {
    "add_task",
    "delete_task",
    "complete_task",
    "show_tasks",
    "reschedule_task",
    "unknown",
}


def make_unknown(original_text, error=None):
    result = {field: None for field in FIELDS}
    result["intent"] = "unknown"
    result["raw_text"] = original_text
    if error:
        result["error"] = error
    return result


def parse_with_transformer(text):
    """Convert text from Whisper into structured scheduler command data."""

    if not isinstance(text, str) or not text.strip():
        return make_unknown("", "Input text is empty")

    text = text.strip()

    prompt = f"""Interpret this scheduler command and return key-value pairs in JSON format.

Allowed intents: add_task, delete_task, complete_task, show_tasks, reschedule_task, unknown

Example 1:
Command: Add my database assignment tomorrow at 3 PM with high priority
JSON: {{"intent":"add_task","task_name":"database assignment","date":"tomorrow","time":"3 PM","deadline":null,"duration_minutes":null,"priority":"high","rigid":null}}

Example 2:
Command: I need to finish my database assignment before Friday and it will take about two hours.
JSON: {{"intent":"add_task","task_name":"database assignment","date":null,"time":null,"deadline":"Friday","duration_minutes":120,"priority":null,"rigid":null}}

Example 3:
Command: Move my gym session to Saturday at 7 PM.
JSON: {{"intent":"reschedule_task","task_name":"gym session","date":"Saturday","time":"7 PM","deadline":null,"duration_minutes":null,"priority":null,"rigid":null}}

Example 4:
Command: Show me all my tasks for tomorrow.
JSON: {{"intent":"show_tasks","task_name":null,"date":"tomorrow","time":null,"deadline":null,"duration_minutes":null,"priority":null,"rigid":null}}

Command: {text}
JSON:"""

    inputs = tokenizer(
        prompt,
        return_tensors="pt",
        truncation=True,
        max_length=1024,
    )

    outputs = model.generate(
        **inputs,
        max_new_tokens=200,
        do_sample=False,
    )

    raw_output = tokenizer.decode(outputs[0], skip_special_tokens=True)
    return clean_and_validate(raw_output, text)


def clean_and_validate(result, original_text):
    """Parse model output, clean T5 formatting quirks, and verify extracted slots."""

    fields = {field: None for field in FIELDS}
    fields["intent"] = "unknown"
    fields["raw_text"] = original_text

    result = re.sub(r"```(?:json)?", "", result.strip(), flags=re.IGNORECASE).strip()

    # Try full JSON object first
    data = None
    match = re.search(r"\{.*\}", result, re.DOTALL)
    if match:
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            data = None

    # Fallback: extract individual key-value pairs if FLAN-T5 dropped curly braces
    if not isinstance(data, dict):
        data = {}
        pattern = (
            r'"(?P<key>intent|task_name|date|time|deadline|'
            r'duration_minutes|priority|rigid|raw_text)"\s*:\s*'
            r'(?P<value>"(?:[^"\\]|\\.)*"|null|true|false|-?\d+(?:\.\d+)?)'
        )
        for item in re.finditer(pattern, result):
            try:
                data[item.group("key")] = json.loads(item.group("value"))
            except json.JSONDecodeError:
                continue

    for key in FIELDS:
        if key in data:
            fields[key] = data[key]

    # Clean up stringified nulls like "null," or "none"
    for key, val in fields.items():
        if key == "raw_text":
            continue
        if isinstance(val, str):
            cleaned = val.strip().rstrip(",").strip()
            if cleaned.lower() in {"null", "none", ""}:
                fields[key] = None
            else:
                fields[key] = cleaned

    # Validate intent
    intent = str(fields.get("intent") or "").strip().lower()
    if intent not in VALID_INTENTS:
        intent = "unknown"
    fields["intent"] = intent

    # Validate duration
    if fields["duration_minutes"] is not None:
        try:
            dur = int(fields["duration_minutes"])
            fields["duration_minutes"] = dur if dur > 0 else None
        except (ValueError, TypeError):
            fields["duration_minutes"] = None

    # Validate priority
    if fields["priority"] is not None:
        p = str(fields["priority"]).lower().strip()
        fields["priority"] = p if p in {"low", "medium", "high"} else None

    # Validate rigid
    if isinstance(fields["rigid"], str):
        r = fields["rigid"].lower().strip()
        fields["rigid"] = True if r == "true" else (False if r == "false" else None)
    elif not isinstance(fields["rigid"], bool):
        fields["rigid"] = None

    # Ground-truth verification for dates, times, deadlines, and priorities
    norm = normalize(original_text)
    rule_parsed = parse_command(original_text)

    if fields["intent"] == "unknown" and rule_parsed["intent"] != "unknown":
        fields["intent"] = rule_parsed["intent"]

    # Always use normalized time/date/deadline extraction so T5 doesn't put times into date or hallucinate minutes
    verified_time = extract_time(norm)
    verified_date = extract_date(norm)
    verified_deadline = extract_deadline(norm)

    fields["time"] = verified_time
    fields["deadline"] = verified_deadline
    if verified_deadline and verified_date == verified_deadline:
        fields["date"] = None
    else:
        fields["date"] = verified_date

    if fields["intent"] == "show_tasks":
        fields["task_name"] = None

    if fields["priority"] is None:
        fields["priority"] = extract_priority(norm)

    if fields["duration_minutes"] is None:
        fields["duration_minutes"] = extract_duration(norm)

    if fields["rigid"] is None:
        fields["rigid"] = extract_rigid(norm)

    if not fields["task_name"] and rule_parsed["task_name"]:
        fields["task_name"] = rule_parsed["task_name"]

    fields["raw_text"] = original_text
    return fields


if __name__ == "__main__":
    print("\nTransformer Parser Test")
    print("-----------------------")

    while True:
        sentence = input("\nEnter a scheduler command (or 'exit'): ").strip()
        if sentence.lower() in {"exit", "quit"}:
            break

        result = parse_with_transformer(sentence)
        print("\nRESULT:")
        print(json.dumps(result, indent=4))