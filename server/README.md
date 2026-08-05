# InkNest Server

[English](README.md) | [简体中文](README.zh-CN.md)

InkNest Server is the Python/FastAPI backend for account-backed backup and
local-first synchronization. It currently provides the service skeleton,
PostgreSQL and MinIO adapters, health endpoints, the first account/session API,
user-scoped library metadata persistence, and presigned asset upload sessions.
Notebook synchronization and upload completion verification are not implemented yet.

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

Also set `INKNEST_JWT_SECRET` in `server/.env` to a random value of at least 32
characters. Generate one without printing it into source control, for example:

```bash
openssl rand -hex 32
```

Store the generated value only in the ignored `.env` files or a production
secrets manager.

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

The API already has non-secret defaults. Only when the Compose API container
needs different optional values, create its ignored override file:

```bash
cp server/.env.compose.example server/.env.compose
```

Do not create this file merely to duplicate defaults. Container-only network
addresses and service credential mappings remain explicit in `compose.yaml`.

Then, from the repository root:

```bash
docker compose up -d --build
```

The values in `.env.example` are development-only. Set unique credentials and
use a secrets manager before any public deployment.

## Local access map

These addresses are the same whether the API runs on the host or through the
default Compose port mapping. `127.0.0.1` and `localhost` are interchangeable
for normal local development.

### API documentation and health

| Content | Address | Notes |
| --- | --- | --- |
| Swagger UI | `http://127.0.0.1:8000/docs` | Interactive API documentation and request testing. |
| Authentication section | `http://127.0.0.1:8000/docs#/authentication` | Swagger section for account and device routes. |
| ReDoc | `http://127.0.0.1:8000/redoc` | Read-only alternative API documentation. |
| OpenAPI JSON | `http://127.0.0.1:8000/openapi.json` | Machine-readable API contract. |
| Liveness | `http://127.0.0.1:8000/api/v1/health/live` | Confirms that the API process is running; it does not check PostgreSQL or MinIO. |
| Readiness | `http://127.0.0.1:8000/api/v1/health/ready` | Confirms that PostgreSQL and the private MinIO bucket are reachable. |

There is currently no route at `/`, so `http://127.0.0.1:8000/` returning
`404 Not Found` is expected. Use `/docs` as the browser entry point.

### API routes

All application routes use the base URL `http://127.0.0.1:8000/api/v1`.

| Method | Route | Authentication | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health/live` | No | API process liveness. |
| `GET` | `/health/ready` | No | PostgreSQL and MinIO readiness. |
| `POST` | `/auth/register` | No | Create a user, device, and session. |
| `POST` | `/auth/login` | No | Sign in and create a device session. |
| `POST` | `/auth/refresh` | Refresh Token in body | Rotate the Refresh Token and issue a new Access Token. |
| `POST` | `/auth/logout` | Refresh Token in body | Revoke the supplied Refresh Token. |
| `GET` | `/me` | Bearer Access Token | Return the current user. |
| `GET` | `/devices` | Bearer Access Token | List the current user's devices. |
| `DELETE` | `/devices/{device_id}` | Bearer Access Token | Revoke one device owned by the current user. |
| `POST` | `/assets/upload-sessions` | Bearer Access Token | Create or retry an upload session and return a MinIO presigned PUT URL. |
| `DELETE` | `/assets/upload-sessions/{upload_id}` | Bearer Access Token | Cancel one pending upload session owned by the current user. |

For Bearer-protected routes, send the Access Token returned by register, login,
or refresh:

```http
Authorization: Bearer <access-token>
```

Failed login attempts use a five-minute sliding window. By default, the API
allows five failures for the same client IP and normalized email, and 25 total
failures from one client IP. A blocked request returns `429 Too Many Requests`,
the structured error code `login_rate_limited`, and a `Retry-After` header.
Successful login clears the account/client failure bucket.

### Presigned asset uploads

An owned notebook must already exist before an upload session can be created.
There is no public notebook CRUD API yet, so use repository code, test data, or
a database tool to prepare one during this phase.

The App submits its stable local asset ID, notebook ID, filename, media type,
byte length, and SHA-256 to `POST /assets/upload-sessions`. The response contains
a short-lived `uploadUrl`, `PUT` method, and required `Content-Type` header. Send
the bytes directly to that private MinIO URL. Treat the signed URL as a temporary
secret and never log or persist it long-term.

Retrying the same asset ID with identical metadata reuses the pending session
and signs a fresh URL. Different metadata returns `409` instead of silently
overwriting a different local file. A successful MinIO PUT intentionally leaves
`asset_uploads.status` as `pending` and creates no `assets` row. The next backend
slice will verify the stored object's actual size and SHA-256 before making it
ready.
Cancelling a session prevents later server-side completion but cannot revoke an
already issued URL before that URL expires. Scheduled cleanup of incomplete and
orphaned objects is a later phase.

### PostgreSQL and MinIO

| Service | Address | How to access |
| --- | --- | --- |
| PostgreSQL | `localhost:5432` | Connect with Navicat, pgAdmin, or `psql`; read database name, user, and password from the ignored root `.env`. |
| MinIO Console | `http://localhost:9001` | Browser administration UI; use the ignored root `.env` MinIO credentials. |
| MinIO S3 API | `http://localhost:9000` | S3-compatible API used by the backend; it is not a normal browser file page. |

The MinIO bucket is private. Files will be accessed through backend-controlled
operations or time-limited signed URLs when asset APIs are implemented, not by
making the bucket publicly browsable.

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

The migration history currently contains:

- `20260805_0001`: intentionally empty baseline.
- `20260805_0002`: `users`, `devices`, and `refresh_tokens`.
- `20260805_0003`: `folders`, `notebooks`, `pages`, `infinite_canvases`, and
  `assets` metadata.
- `20260805_0004`: current JSON content and hashes on notebooks, pages, and
  infinite canvases, plus immutable `revisions` history.
- `20260805_0005`: pending `asset_uploads` sessions with expected size,
  SHA-256, object key, state, and expiry timestamps.

Future schema work must add a new revision instead of rewriting an applied
revision.

```bash
uv run alembic upgrade head
uv run alembic current
```

To create a migration after changing SQLAlchemy models:

```bash
uv run alembic revision --autogenerate -m "describe the schema change"
```

Always inspect the generated `upgrade()` and `downgrade()` before applying it.
To safely undo only the newest development migration, first back up important
data, then run `uv run alembic downgrade -1`. Downgrading can delete tables or
columns and is not a routine cleanup command.

## Library metadata persistence

SQLAlchemy models in `src/inknest_server/models/library.py` define folders,
notebooks, pages, infinite canvases, and asset metadata. The repository in
`src/inknest_server/repositories/library.py` is the database-access boundary.
It requires a `user_id` for every read and validates ownership before creating
children, so a missing resource and another user's resource have the same
not-found outcome.

Client-created IDs are stored as stable strings and form a composite key with
`user_id`. Two users can therefore both upload a local object named
`page-local-1` without collision. Page `coordinate_space_version` uses JSON so
an unknown future representation can be preserved without server rewriting.
The `assets` table stores only object metadata and MinIO object keys; file bytes
remain in MinIO.

There are no public library CRUD or synchronization routes yet; upload sessions
are the only public library-related routes. Inspect these tables in
Navicat/pgAdmin, or run the repository tests from `server/`:

```bash
uv run pytest tests/unit/test_library_repository.py
INKNEST_RUN_INTEGRATION=1 uv run pytest tests/integration
```

## Revisioned JSON content

Notebook, page, and infinite-canvas rows now hold the latest complete JSON
object in `content`, its server-owned `revision`, and a SHA-256 `content_hash`.
For a page, this JSON is where strokes, text boxes, image placement, shapes,
PDF-background references, and unknown fields are preserved together. Every
changed save also appends the same snapshot to the immutable `revisions` table;
the server does not store one database row per pen stroke.

Hashes use UTF-8 JSON with recursively sorted object keys, no insignificant
whitespace, preserved array order and Unicode, and rejected NaN/Infinity
values. The server normalizes and hashes content without interpreting or
rewriting unknown `coordinateSpaceVersion` values.

Content writes require the caller's current `base_revision`. PostgreSQL locks
the resource row, the server assigns the next revision, and a stale base with
different content raises a revision conflict. Retrying identical content is a
no-op even if the retry still carries the previous base revision, so it does
not create duplicate history. This repository behavior is ready for a future
sync service but is not exposed through HTTP yet.

## Authentication API

The API uses email/password accounts, Argon2id password hashes, short-lived
JWT access tokens, and rotating opaque refresh tokens. Only a SHA-256 hash of
each refresh token is stored in PostgreSQL.

- `POST /api/v1/auth/register`: create a user, device, and session.
- `POST /api/v1/auth/login`: verify credentials and create a device session.
- `POST /api/v1/auth/refresh`: rotate the refresh token and issue a new access
  token.
- `POST /api/v1/auth/logout`: revoke the supplied refresh token.
- `GET /api/v1/me`: inspect the current user with a Bearer access token.
- `GET /api/v1/devices`: list only the current user's devices.
- `DELETE /api/v1/devices/{device_id}`: revoke one owned device and its refresh
  tokens.

Use Swagger at `http://localhost:8000/docs` to inspect request examples and
responses. The first API slice does not send verification email.

The current limiter is process-local, matching the single-process development
topology. Before running multiple API instances, replace its storage with a
shared implementation so every instance observes the same attempt window.

## Configuration layers

All application settings use the `INKNEST_` prefix. Configuration is split by
responsibility so new optional settings do not have to be copied into
`compose.yaml`.

| File or source | Purpose | Tracked |
| --- | --- | --- |
| Pydantic `Settings` | Non-secret application defaults and validation. | Yes |
| `server/.env` | Host-run FastAPI values such as `localhost` dependency addresses. | No |
| Root `.env` | Compose infrastructure, ports, service credentials, and interpolation. | No |
| `server/.env.compose` | Optional non-secret overrides for the Compose API container. | No |
| `compose.yaml` `environment` | Container-only addresses and explicit service-to-service credential mapping. | Yes |

Examples are provided by `.env.example`, `server/.env.example`, and
`server/.env.compose.example`. `environment` overrides the same key from
`env_file`; this is intentional for container-only values such as the
PostgreSQL host `postgres` and MinIO host `minio`.

When adding a normal optional API setting, add its Pydantic default, validation,
example, and documentation. Add it to `compose.yaml` only when the container
must receive a different value or an explicitly mapped secret.

Important settings:

- `INKNEST_DATABASE_URL`: SQLAlchemy PostgreSQL URL.
- `INKNEST_MINIO_ENDPOINT`: MinIO host and port without a URL scheme.
- `INKNEST_MINIO_PUBLIC_ENDPOINT`: client-visible MinIO host and port embedded
  in signed URLs. Compose normally uses `localhost:9000` here and `minio:9000`
  for the internal endpoint. For a physical device, configure a LAN-reachable
  host or HTTPS domain instead of `localhost`.
- `INKNEST_MINIO_ACCESS_KEY` and `INKNEST_MINIO_SECRET_KEY`: server-only
  credentials; never expose them to Flutter.
- `INKNEST_MINIO_BUCKET`: private object bucket checked by readiness.
- `INKNEST_MINIO_SECURE`: enable TLS for non-local storage endpoints.
- `INKNEST_MINIO_PUBLIC_SECURE`: use HTTPS in client-visible signed URLs.
- `INKNEST_ASSET_UPLOAD_URL_MINUTES`: signed upload URL lifetime, default 15.
- `INKNEST_ASSET_UPLOAD_SESSION_HOURS`: pending-session lifetime, default 24.
- `INKNEST_MAX_ASSET_UPLOAD_BYTES`: per-asset limit, default 512 MiB.
- `INKNEST_JWT_SECRET`: server-only signing secret, at least 32 characters;
  never expose it to Flutter or commit a production value.
- `INKNEST_ACCESS_TOKEN_MINUTES`: access-token lifetime, default 15 minutes.
- `INKNEST_REFRESH_TOKEN_DAYS`: refresh-token lifetime, default 30 days.
- `INKNEST_LOGIN_RATE_LIMIT_ACCOUNT_ATTEMPTS`: failures allowed for one client
  IP and normalized email per window, default 5.
- `INKNEST_LOGIN_RATE_LIMIT_IP_ATTEMPTS`: total failures allowed for one client
  IP per window, default 25.
- `INKNEST_LOGIN_RATE_LIMIT_WINDOW_SECONDS`: login-limit sliding-window length,
  default 300 seconds.
