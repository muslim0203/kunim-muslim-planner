# KUNIM API — multi-stage image.
#
# Build context is the REPO ROOT (see infra/docker-compose.yml:
# `build.context: ../`, `build.dockerfile: infra/api.Dockerfile`), so every
# COPY below is written relative to the repo root, e.g. `apps/api/...`.
#
# NOT built or run on the machine that authored this file: Docker is not
# installed here (see infra/README.md). This Dockerfile has only been
# reviewed by eye for syntax/path correctness — it has never been through
# `docker build`. Verify on a machine with Docker before relying on it.

# ---------------------------------------------------------------------------
# Stage 1: builder — resolve and install dependencies into a venv.
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Build-time system deps: gcc/build-essential + libffi/libpq headers cover
# the packages in apps/api/pyproject.toml that may need to compile a C
# extension (argon2-cffi -> cffi -> libffi; asyncpg ships manylinux wheels
# for glibc so this is mostly a safety net).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /venv
ENV PATH="/venv/bin:${PATH}"

WORKDIR /build

# Copy only what's needed to resolve dependencies + install the package.
COPY apps/api/pyproject.toml apps/api/README.md ./apps/api/
COPY apps/api/app ./apps/api/app

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir ./apps/api

# ---------------------------------------------------------------------------
# Stage 2: runtime — slim image, non-root user, no build toolchain.
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app/apps/api \
    PATH="/venv/bin:${PATH}"

RUN groupadd --system kunim && useradd --system --gid kunim --home /app kunim

COPY --from=builder /venv /venv

WORKDIR /app

# App source, laid out the same way as the repo (`apps/api/app/...`) so
# `--app-dir apps/api` behaves identically whether this directory came from
# the image (prod) or a dev bind-mount over it (see docker-compose.yml).
COPY apps/api ./apps/api

# Role-selecting default command (see infra/start.sh). Line endings are
# normalised in case the file was checked out with CRLF on Windows.
COPY infra/start.sh /usr/local/bin/kunim-start
RUN sed -i 's/\r$//' /usr/local/bin/kunim-start \
    && chmod 0755 /usr/local/bin/kunim-start

RUN chown -R kunim:kunim /app
USER kunim

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=3)" || exit 1

# Default command for a plain `docker run` and for platforms that cannot
# override it per service (Railway): KUNIM_ROLE=api applies migrations and
# serves on $PORT, KUNIM_ROLE=worker runs arq. docker-compose files set their
# own `command:` for dev (--reload) and for the `worker` service.
CMD ["kunim-start"]
