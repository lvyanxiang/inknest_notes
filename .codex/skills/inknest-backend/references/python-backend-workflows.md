# InkNest Python Backend Workflows

Use only the sections affected by the current task. Explain them in the user's
language and distinguish first-time setup from everyday commands.

## Contents

- Node.js mental model
- Daily development startup
- Database schema change
- Python dependency change
- FastAPI route change
- PostgreSQL and MinIO inspection
- Verification and troubleshooting

## Node.js Mental Model

| InkNest Python tool | Approximate Node.js analogue |
| --- | --- |
| FastAPI | Express or NestJS HTTP layer |
| SQLAlchemy | Prisma Client, TypeORM, or Sequelize |
| Alembic | Prisma Migrate or TypeORM/Sequelize migrations |
| Pydantic | Zod plus typed configuration |
| `uv` | npm/pnpm plus Python environment management |
| Uvicorn `--reload` | Node development server or nodemon |
| pytest | Jest or Vitest |
| Ruff | ESLint plus formatter |
| mypy | TypeScript-style static checking for Python |

These are learning analogies, not claims of identical APIs.

## Daily Development Startup

From the repository root, keep only infrastructure in Docker:

```bash
docker compose stop api
docker compose up -d postgres minio minio-init
```

From `server/`, prepare once and then start the host API:

```bash
uv sync
uv run alembic upgrade head
uv run uvicorn inknest_server.main:app --reload
```

On later runs, only the Uvicorn command is normally required. Verify through
`/docs`, `/api/v1/health/live`, and `/api/v1/health/ready`. Stop with `Ctrl+C`.

## Database Schema Change

Explain and perform the workflow in this order:

1. Add or change a SQLAlchemy model under `server/src/inknest_server/`.
2. Ensure its module is imported so `Base.metadata` contains the table.
3. From `server/`, generate a migration:

   ```bash
   uv run alembic revision --autogenerate -m "describe the schema change"
   ```

4. Read the generated file under `server/alembic/versions/`. Verify names,
   types, defaults, indexes, constraints, foreign keys, and both `upgrade()`
   and `downgrade()`; autogeneration is a proposal, not proof of correctness.
5. Apply and inspect:

   ```bash
   uv run alembic upgrade head
   uv run alembic current
   uv run alembic history
   ```

6. Inspect PostgreSQL in Navicat/pgAdmin, run focused tests, and then run the
   complete `uv run pytest` suite.

Use `uv run alembic downgrade -1` only for a reviewed development rollback.
Warn that downgrades can delete columns, tables, or data. Never rewrite a
migration that may already have been applied elsewhere; add a new revision.

## Python Dependency Change

From `server/`, add runtime or development dependencies with:

```bash
uv add package-name
uv add --dev package-name
uv sync
```

`uv add` updates `pyproject.toml` and `uv.lock`; `uv sync` makes the local
environment match the lockfile. Explain why the dependency is needed and do
not add a package when the standard library or an existing dependency suffices.

## FastAPI Route Change

Add the request/response schema, service behavior, versioned router under
`/api/v1`, and tests together. Start Uvicorn, inspect `/docs`, call the route,
and describe the successful status/body plus important error responses. Keep
database access in services/repositories rather than embedding all logic in a
route function.

## PostgreSQL And MinIO Inspection

Use `localhost:5432` and values from the ignored environment file when a host
database GUI connects to PostgreSQL. Explain that `alembic_version` records the
applied migration head; it is not an audit log of every row or field change.
Do not assume values in `.env.example` match the ignored local `.env`, and do
not print local passwords. For container-side inspection, prefer the variables
already injected into the PostgreSQL container, for example:

```bash
docker compose exec postgres sh -lc \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version_num FROM alembic_version;"'
```

Use `http://localhost:9001` for MinIO Console and port `9000` for the S3 API.
Inspect the private `inknest-private` bucket, object keys, metadata, and sizes.
Keep notebook ownership and object references in PostgreSQL, not in MinIO.

## Verification And Troubleshooting

From `server/`, run:

```bash
uv run ruff format --check .
uv run ruff check .
uv run mypy
uv run pytest
```

From the repository root, use these commands as relevant:

```bash
docker compose ps
docker compose logs postgres
docker compose logs minio
docker compose config
```

Do not suggest `docker compose down -v` without an explicit warning that it
deletes PostgreSQL and MinIO development data.
