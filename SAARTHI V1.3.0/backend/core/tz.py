"""Single source of truth for the app's timezone.

Everything AURA computes — task timestamps, scheduler day windows, the
hour_of_day recorded on events and fed to the ML models — is in IST.
DB columns are timestamptz, so they still store absolute instants; this
only fixes what the app *means* when it says "08:00".
"""
from datetime import datetime
from zoneinfo import ZoneInfo

# Asia/Kolkata has no DST, so `.replace(hour=...)` on an IST-aware datetime
# is safe. Do not copy that pattern to a zone that observes DST.
IST = ZoneInfo("Asia/Kolkata")


def now() -> datetime:
    return datetime.now(IST)
