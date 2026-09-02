cd "/media/shubham/New Volume/ACADEMICS/Capstone/Aura/Aura"

# 1. db + redis via Docker
docker compose up -d db redis

# 2. point the local api at those containers
export DATABASE_URL=postgresql+asyncpg://aura_user:aura_pass@localhost:5432/aura_db
export REDIS_URL=redis://localhost:6379/0

# 3. activate the linux conda env
conda activate ./.venv-linux

# 4. run the api (new terminal, or background with nohup/&)
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# 5. run the dashboard (another terminal, same env activated)
streamlit run dashboard.py --server.port 8501


docker exec aura_postgres psql -U aura_user -d aura_db -c \
  "TRUNCATE tasks, task_events, scheduled_slots;"
