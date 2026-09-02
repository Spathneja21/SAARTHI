from datetime import datetime, timezone
from core.tz import now as ist_now
from sqlalchemy.ext.asyncio import AsyncSession
from models.models import StressLog


def _now():
    return ist_now()


def compute_stress_score(
    heart_rate          : int,
    hrv_ms              : float,
    app_switches        : int,
    screen_time_hours   : float,
    minutes_since_break : int,
) -> int:
    """
    Composite stress score 0-100 from biometric signals.
    Each signal contributes a weighted component.
    """
    # High HR = more stress
    hr_stress = max(0, min(100, int((heart_rate - 70) * 2)))

    # Low HRV = more stress (HRV drops when stressed)
    hrv_stress = max(0, min(100, int((80 - hrv_ms) * 1.5)))

    # Rapid app switching = distraction/stress
    switch_stress = min(100, app_switches * 8)

    # Long screen time without break = fatigue
    screen_stress = min(100, int(screen_time_hours * 15))

    # Time since last break
    break_stress = min(100, int(minutes_since_break * 1.2))

    score = int(
        hr_stress     * 0.25 +
        hrv_stress    * 0.30 +
        switch_stress * 0.20 +
        screen_stress * 0.10 +
        break_stress  * 0.15
    )
    return min(score, 100)


def get_stress_level(score: int) -> str:
    if score < 30:  return "calm"
    if score < 55:  return "elevated"
    if score < 75:  return "high"
    return "critical"


def get_nudge_type(score: int, minutes_since_break: int,
                   app_switches: int, screen_time_hours: float) -> str:
    if score < 30:
        return "none"
    if minutes_since_break > 90:
        return "break"
    if app_switches > 8:
        return "reprioritize"
    if score >= 70:
        return "breathing"
    if screen_time_hours > 3:
        return "hydrate"
    return "break"


def get_nudge_message(nudge_type: str, minutes_since_break: int,
                      screen_time_hours: float) -> str:
    messages = {
        "breathing":    "Your stress is high. Take 4 deep breaths — it only takes 30 seconds.",
        "break":        f"You have been focused for {minutes_since_break} minutes. A 5-minute break will help.",
        "reprioritize": "You are switching apps rapidly. Pick one task and focus on it.",
        "hydrate":      f"You have had {screen_time_hours:.1f} hours of screen time. Drink some water and stretch.",
        "none":         "You are calm and focused. Keep going!",
    }
    return messages.get(nudge_type, "Take a moment for yourself.")


async def evaluate_and_log(
    user_id             : object,
    heart_rate          : int,
    hrv_ms              : float,
    app_switches        : int,
    screen_time_hours   : float,
    minutes_since_break : int,
    db                  : AsyncSession,
) -> dict:
    now   = _now()
    score = compute_stress_score(
        heart_rate, hrv_ms, app_switches,
        screen_time_hours, minutes_since_break
    )
    level  = get_stress_level(score)
    nudge  = get_nudge_type(score, minutes_since_break, app_switches, screen_time_hours)
    message= get_nudge_message(nudge, minutes_since_break, screen_time_hours)

    # Persist to stress_logs for ML training
    log = StressLog(
        user_id             = user_id,
        heart_rate          = heart_rate,
        hrv_ms              = hrv_ms,
        app_switches        = app_switches,
        screen_time_hours   = screen_time_hours,
        minutes_since_break = minutes_since_break,
        stress_score        = score,
        stress_level        = level,
        nudge_type          = nudge,
        hour_of_day         = now.hour,
        day_of_week         = now.weekday(),
        recorded_at         = now,
    )
    db.add(log)
    await db.commit()

    return {
        "stress_score"      : score,
        "stress_level"      : level,
        "should_intervene"  : score >= 35,
        "nudge_type"        : nudge,
        "message"           : message,
    }