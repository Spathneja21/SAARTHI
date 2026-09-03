from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Copy .env.example to .env and fill it in, "
        "or export it before starting the app."
    )

# Logs every SQL statement when on. Off by default — it is overwhelming in normal use.
SQL_ECHO = os.getenv("SQL_ECHO", "false").lower() in ("1", "true", "yes")

engine = create_async_engine(DATABASE_URL, echo=SQL_ECHO)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session

async def create_tables():
    from models.models import Base
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)