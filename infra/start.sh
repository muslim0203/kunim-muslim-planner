#!/bin/sh
# Default command of the API image (infra/api.Dockerfile).
#
# Platforms such as Railway run the image's default command for every
# service built from it, so the process is selected by KUNIM_ROLE:
#   api (default) - apply database migrations, then serve on $PORT
#   worker        - run the arq background worker
# docker-compose files still override `command:` where they need something
# else (e.g. dev --reload).
set -e

case "${KUNIM_ROLE:-api}" in
  api)
    cd /app/apps/api
    alembic upgrade head
    exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
    ;;
  worker)
    exec arq app.jobs.worker.WorkerSettings
    ;;
  *)
    echo "Unknown KUNIM_ROLE (expected api or worker)" >&2
    exit 64
    ;;
esac
