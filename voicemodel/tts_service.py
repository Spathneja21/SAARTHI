import csv
import os
import winsound
import soundfile as sf
from pocket_tts import TTSModel

print("Loading Pocket TTS model...")
_tts_model = TTSModel.load_model()
_voice_state = _tts_model.get_state_for_audio_prompt("alba")
print("Pocket TTS loaded successfully!")


def format_duration(minutes):
    """Convert integer minutes into natural spoken text."""
    if not minutes:
        return ""
    minutes = int(minutes)
    hours, mins = divmod(minutes, 60)
    parts = []
    if hours:
        parts.append(f"{hours} hour" + ("s" if hours > 1 else ""))
    if mins:
        parts.append(f"{mins} minute" + ("s" if mins > 1 else ""))
    return " and ".join(parts)


def format_time_for_speech(time_str):
    """Clean time strings so TTS pronounces them naturally (e.g., '11:20 AM' -> '11 20 AM')."""
    if not time_str:
        return ""
    return time_str.replace(":00", "").replace(":", " ")


def build_response(parsed_cmd, tasks_csv_path="tasks.csv"):
    """Generate a natural conversational response from a parsed command dictionary."""
    intent = parsed_cmd.get("intent", "unknown")
    task = parsed_cmd.get("task_name") or "your task"
    date = parsed_cmd.get("date")
    time_str = format_time_for_speech(parsed_cmd.get("time"))
    deadline = parsed_cmd.get("deadline")
    duration = parsed_cmd.get("duration_minutes")
    priority = parsed_cmd.get("priority")

    if intent == "add_task":
        msg = f"Okay, I have scheduled {task}"
        if date:
            msg += f" for {date}"
        if time_str:
            msg += f" at {time_str}"
        msg += "."
        if duration:
            msg += f" I've blocked out {format_duration(duration)} for it."
        if deadline:
            msg += f" The deadline is set for {deadline}."
        if priority:
            msg += f" Marked as {priority} priority."
        return msg

    if intent == "reschedule_task":
        msg = f"Got it. I have moved {task}"
        if date:
            msg += f" to {date}"
        if time_str:
            msg += f" at {time_str}"
        msg += "."
        return msg

    if intent == "delete_task":
        return f"Okay, I have removed {task} from your schedule."

    if intent == "complete_task":
        return f"Great job! I have marked {task} as completed."

    if intent == "show_tasks":
        return build_schedule_summary(date_filter=date, tasks_csv_path=tasks_csv_path)

    return "Sorry, I didn't quite catch that scheduler command. Could you please repeat it?"


def build_schedule_summary(date_filter=None, tasks_csv_path="tasks.csv"):
    """Read tasks from CSV and build a spoken summary (optionally filtered by date)."""
    if not os.path.exists(tasks_csv_path):
        return "You don't have any tasks saved in your schedule yet."

    matching_tasks = []
    with open(tasks_csv_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            row_date = (row.get("date") or "").strip()
            if date_filter and row_date.lower() != date_filter.lower():
                continue
            matching_tasks.append(row)

    if not matching_tasks:
        if date_filter:
            return f"You have no tasks scheduled for {date_filter}."
        return "Your schedule is currently empty."

    header = (
        f"You have {len(matching_tasks)} task"
        + ("s" if len(matching_tasks) > 1 else "")
        + (f" for {date_filter}: " if date_filter else " in your schedule: ")
    )

    items = []
    for row in matching_tasks:
        t_name = (row.get("task_name") or "").strip()
        t_date = (row.get("date") or "").strip()
        t_time = format_time_for_speech((row.get("time") or "").strip())
        part = t_name
        if t_date and not date_filter:
            part += f" on {t_date}"
        if t_time:
            part += f" at {t_time}"
        items.append(part)

    return header + ", ".join(items) + "."


def speak(text, output_wav="tts_out.wav", play_audio=True):
    """Synthesize speech from text using Pocket TTS and play it aloud."""
    print(f"\n[ASSISTANT]: {text}")
    audio = _tts_model.generate_audio(_voice_state, text)
    sf.write(output_wav, audio.numpy(), _tts_model.sample_rate)
    if play_audio:
        winsound.PlaySound(output_wav, winsound.SND_FILENAME)
    return output_wav


def speak_command_result(parsed_cmd, tasks_csv_path="tasks.csv", play_audio=True):
    """Build the appropriate conversational response for a parsed command and speak it."""
    response_text = build_response(parsed_cmd, tasks_csv_path=tasks_csv_path)
    speak(response_text, play_audio=play_audio)
    return response_text
