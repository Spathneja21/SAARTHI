import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from celery import Celery
from celery.schedules import crontab
import os
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

celery_app = Celery(
    "aura",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["workers.tasks"],
)

celery_app.conf.update(
    task_serializer   = "json",
    accept_content    = ["json"],
    result_serializer = "json",
    timezone          = "UTC",
    enable_utc        = True,
)

# Scheduled jobs
celery_app.conf.beat_schedule = {
    "weekly-retrain": {
        "task"    : "workers.tasks.retrain_models",
        "schedule": crontab(day_of_week="sun", hour=2, minute=0),
    },
    "daily-profile-update": {
        "task"    : "workers.tasks.update_behavior_profiles",
        "schedule": crontab(hour=0, minute=30),
    },
    "daily-rl-rewards": {
        "task"    : "workers.tasks.update_rl_rewards",
        "schedule": crontab(hour=1, minute=0),  # 01:00 UTC daily
    },
}