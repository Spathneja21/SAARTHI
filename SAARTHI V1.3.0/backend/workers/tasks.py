import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import asyncio
import logging
from workers.celery_app import celery_app

logger = logging.getLogger(__name__)


def _run(coro):
    """Run async code in a brand new event loop — never reuse."""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()
        asyncio.set_event_loop(None)


def _make_session():
    """
    Create a fresh async engine + session for this task.
    Never import the shared engine — it belongs to a different loop.
    """
    import os
    from dotenv import load_dotenv
    load_dotenv()

    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

    url = os.getenv("DATABASE_URL")
    engine = create_async_engine(url, echo=False)
    Session = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    return engine, Session


@celery_app.task(name="workers.tasks.retrain_models", bind=True, max_retries=3)
def retrain_models(self):
    async def _retrain():
        from ml.ml_features import extract_features
        from ml.ml_train import train
        from ml.lgbm_train import train_procrastination

        engine, Session = _make_session()
        try:
            async with Session() as db:
                df = await extract_features(db)
        finally:
            await engine.dispose()

        if df.empty or len(df) < 10:
            logger.info("Not enough data to retrain — skipping.")
            return {"status": "skipped", "reason": "not enough data"}

        xgb_metrics  = train(df)
        lgbm_metrics = train_procrastination(df)

        logger.info("XGBoost: %s", xgb_metrics)
        logger.info("LightGBM: %s", lgbm_metrics)

        return {
            "status"      : "complete",
            "xgb_metrics" : xgb_metrics,
            "lgbm_metrics": lgbm_metrics,
        }

    try:
        return _run(_retrain())
    except Exception as exc:
        logger.error("Retrain failed: %s", exc)
        raise self.retry(exc=exc, countdown=60)


@celery_app.task(name="workers.tasks.update_behavior_profiles", bind=True, max_retries=3)
def update_behavior_profiles(self):
    async def _update():
        from models.models import User
        from services.analytics_service import build_behavior_profile
        from sqlalchemy import select

        engine, Session = _make_session()
        try:
            async with Session() as db:
                result = await db.execute(
                    select(User).where(User.is_active == True)
                )
                user_ids = [u.id for u in result.scalars().all()]
        finally:
            await engine.dispose()

        updated = 0
        for user_id in user_ids:
            eng2, Sess2 = _make_session()
            try:
                async with Sess2() as db:
                    await build_behavior_profile(user_id, db)
                updated += 1
            except Exception as e:
                logger.error("Profile failed for %s: %s", user_id, e)
            finally:
                await eng2.dispose()

        return {"status": "complete", "users_updated": updated}

    try:
        return _run(_update())
    except Exception as exc:
        logger.error("Profile update failed: %s", exc)
        raise self.retry(exc=exc, countdown=60)


@celery_app.task(name="workers.tasks.retrain_on_demand")
def retrain_on_demand():
    return retrain_models.apply().get()


@celery_app.task(name="workers.tasks.update_rl_rewards")
def update_rl_rewards():
    """
    Daily task — compute RL rewards from completed preference feedback.
    Reward signal:
      +20 if task completed on time in user-chosen slot
      +10 if user kept AURA's suggestion and completed
      -5  if user moved the slot
      -10 if task was abandoned after rescheduling
    """
    async def _update():
        from core.database import AsyncSessionLocal
        from models.models import SlotPreferenceFeedback, Task, TaskStatus
        from sqlalchemy import select

        engine, Session = _make_session()
        try:
            async with Session() as db:
                result = await db.execute(
                    select(SlotPreferenceFeedback).where(
                        SlotPreferenceFeedback.reward == None   # noqa
                    )
                )
                feedbacks = result.scalars().all()

                for fb in feedbacks:
                    task_result = await db.execute(
                        select(Task).where(Task.id == fb.task_id)
                    )
                    task = task_result.scalar_one_or_none()
                    if task is None:
                        continue

                    if task.status == TaskStatus.COMPLETED:
                        reward = 20.0 if fb.was_kept else 10.0
                        fb.was_completed = True
                    elif task.status == TaskStatus.ABANDONED:
                        reward = -10.0
                        fb.was_completed = False
                    elif not fb.was_kept:
                        reward = -5.0
                    else:
                        continue   # task not resolved yet

                    fb.reward = reward

                await db.commit()
        finally:
            await engine.dispose()

    return _run(_update())