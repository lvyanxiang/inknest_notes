# InkNest Server

InkNest Server is the Python/FastAPI backend for account-backed backup and
local-first synchronization. Phase 1 provides the service skeleton,
PostgreSQL and MinIO adapters, Alembic baseline, health endpoints, and tests;
it does not yet implement accounts or notebook sync.

## Requirements

- Docker Desktop with Docker Compose for PostgreSQL and MinIO.
- Python 3.12 and `uv` for running the API on the host during development.

Install `uv` on macOS when needed:

```bash
brew install uv
```

## Recommended development startup

During normal development, run PostgreSQL and MinIO in Docker and run the
FastAPI service directly on the host. This keeps infrastructure isolated while
giving the API automatic reload after Python source changes.

If the Compose API container is already running, stop only that service from
the repository root. PostgreSQL and MinIO remain running:

```bash
docker compose stop api
```

Start or keep the required infrastructure running:

```bash
docker compose up -d postgres minio minio-init
```

On the first host setup, create `server/.env` from the example and replace the
development credentials with the same values used by the root `.env`:

```bash
cp server/.env.example server/.env
```

Do not run that copy command again when `server/.env` already contains the
desired local credentials.

Install dependencies, apply migrations, and start the API:

```bash
cd server
uv sync
uv run alembic upgrade head
uv run uvicorn inknest_server.main:app --reload --host 127.0.0.1 --port 8000
```

After the first setup, the usual API startup command is:

```bash
cd server
uv run uvicorn inknest_server.main:app --reload
```

Stop the host API with `Ctrl+C`.

## Start the complete stack in Docker

Use the complete containerized stack for integration testing or to verify the
same packaged runtime used by deployment. It does not provide host-side Python
hot reload.

On the first setup only, create the root `.env` when it does not exist and set
development credentials. Do not overwrite an existing `.env`:

```bash
cp .env.example .env
```

Then, from the repository root:

```bash
docker compose up -d --build
```

The default development endpoints are:

- API: `http://localhost:8000`
- OpenAPI: `http://localhost:8000/docs`
- Liveness: `http://localhost:8000/api/v1/health/live`
- Readiness: `http://localhost:8000/api/v1/health/ready`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`
- PostgreSQL: `localhost:5432`

The values in `.env.example` are development-only. Set unique credentials and
use a secrets manager before any public deployment.

## Validate

From `server/`:

```bash
uv run ruff format --check .
uv run ruff check .
uv run mypy
uv run pytest
```

With PostgreSQL and MinIO running, include the integration test:

```bash
INKNEST_RUN_INTEGRATION=1 uv run pytest -m integration
```

Validate orchestration from the repository root:

```bash
docker compose config
```

## Database migrations

The initial migration is an intentionally empty baseline. Future schema work
must add a new revision instead of rewriting an applied revision.

```bash
uv run alembic upgrade head
uv run alembic current
uv run alembic downgrade base
```

## Environment variables

All application settings use the `INKNEST_` prefix. See
`server/.env.example` for local host values and the root `.env.example` for
Compose values.

Important settings:

- `INKNEST_DATABASE_URL`: SQLAlchemy PostgreSQL URL.
- `INKNEST_MINIO_ENDPOINT`: MinIO host and port without a URL scheme.
- `INKNEST_MINIO_ACCESS_KEY` and `INKNEST_MINIO_SECRET_KEY`: server-only
  credentials; never expose them to Flutter.
- `INKNEST_MINIO_BUCKET`: private object bucket checked by readiness.
- `INKNEST_MINIO_SECURE`: enable TLS for non-local storage endpoints.
