# AURA Backend

AI-powered productivity backend — FastAPI + PostgreSQL + XGBoost + LightGBM

## Stack
- FastAPI — REST API
- PostgreSQL — database (Docker locally, RDS on AWS)
- SQLAlchemy async — ORM
- XGBoost — task completion predictor (AUC 0.99)
- LightGBM — procrastination risk scorer (AUC 0.95)
- Redis + Celery — background workers
- JWT — authentication

## Setup

### 1. Start database
docker compose up -d

### 2. Install dependencies
pip install -r requirements-core.txt

### 3. Run server
uvicorn main:app --reload

### 4. Open docs
http://localhost:8000/docs

## ML Models
Trained on Gryzzly dataset (4.4M task records, published in Scientific Data 2025)
- XGBoost: task completion predictor
- LightGBM: procrastination risk scorer
- Models stored in ml/artifacts/

## API Endpoints
- POST /register
- POST /login
- POST /tasks
- GET  /tasks
- PATCH /tasks/{id}/transition
- GET  /tasks/{id}/history
- POST /nudge/evaluate
- POST /ml/predict
- POST /ml/predict/procrastination
- POST /analytics/profile/build
- GET  /analytics/profile
- POST /ml/retrain