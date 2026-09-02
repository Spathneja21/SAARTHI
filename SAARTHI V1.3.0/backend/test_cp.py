import asyncio, time
from core.database import AsyncSessionLocal
from models.models import User
from sqlalchemy import select
from saarthi.config import DEFAULT_CONFIG
DEFAULT_CONFIG.w_slot_quality = 0
from services.cpsat_bridge import run_cpsat_schedule

async def test():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User))
        u = res.scalars().first()
        t0 = time.time()
        res = await run_cpsat_schedule(u.id, db)
        print(f'Done in {time.time()-t0:.2f}s, status: {res.get("solve_status")}')

asyncio.run(test())
