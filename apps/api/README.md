# KUNIM API (Phase 0)

FastAPI skeleton. Runs without Postgres/Redis for local dev checks.

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -e ".[dev]"
cp .env.example .env
.venv/Scripts/python -m uvicorn app.main:app --reload
```

Test:

```bash
.venv/Scripts/python -m pytest -q
.venv/Scripts/python -m ruff check .
```

`GET /health` — liveness, no DB. `GET /health/ready` — checks DB/Redis, never raises.
