# InkNest Server

[English](README.md) | [简体中文](README.zh-CN.md)

InkNest Server is the Python/FastAPI backend for account-backed backup and
local-first synchronization. It currently provides the service skeleton,
PostgreSQL and MinIO adapters, health endpoints, the first account/session API,
user-scoped library metadata persistence, verified presigned asset upload and
download flows, an incremental sync change feed with opaque cursors, and atomic
batch sync commits for existing revisioned content. Creating resources through
sync, deletion/tombstones, and conflict copies are not implemented yet.

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
| `POST` | `/assets/upload-sessions/{upload_id}/complete` | Bearer Access Token | Verify the staged object and create ready asset metadata. |
| `DELETE` | `/assets/upload-sessions/{upload_id}` | Bearer Access Token | Cancel one pending upload session owned by the current user. |
| `GET` | `/assets/{asset_id}/download-url` | Bearer Access Token | Sign a short-lived download URL for one ready, owned asset. |
| `GET` | `/sync/changes?cursor=...&limit=...` | Bearer Access Token | Read ordered changes for the current user and receive the next opaque cursor. |
| `POST` | `/sync/commit` | Bearer Access Token | Atomically commit an idempotent batch of existing notebook, page, or infinite-canvas content updates. |

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
the bytes directly to that private MinIO URL. Then call
`POST /assets/upload-sessions/{upload_id}/complete`. Treat the signed URL as a
temporary secret and never log or persist it long-term.

Retrying the same asset ID with identical metadata reuses the pending session
and signs a fresh URL. Different metadata returns `409` instead of silently
overwriting a different local file. A successful MinIO PUT intentionally leaves
the session pending. Completion checks the stored MIME and byte length, copies
the staging object to a server-only final key, streams that copy through
SHA-256, and only then creates one ready `assets` row. Completion retries return
the same asset. A mismatch returns `422`, creates no ready asset, and retains the
staging object so the client can upload corrected bytes and retry.
Cancelling a session prevents later server-side completion but cannot revoke an
already issued URL before that URL expires. The operator-run cleanup command
described below handles expired and residual staging objects after a safety
window.

After completion, request `GET /assets/{asset_id}/download-url`. The server only
signs a ready asset owned by the authenticated user and first checks that its
MinIO object still matches the stored size and media type. The response includes
the URL, expiry, byte length, and SHA-256. Clients must download to temporary
storage, verify size and SHA-256, and only then atomically replace local data.
Never log or retain the complete signed URL.

### Incremental synchronization changes

`GET /api/v1/sync/changes` returns only the authenticated user's append-only
events in server order. The default page size is 100 and the accepted range is
1–500:

```bash
curl 'http://127.0.0.1:8000/api/v1/sync/changes?limit=100' \
  -H 'Authorization: Bearer <access-token>'
```

Persist `nextCursor` only after the App has safely applied the whole page, then
send it back unchanged:

```bash
curl --get 'http://127.0.0.1:8000/api/v1/sync/changes' \
  -H 'Authorization: Bearer <access-token>' \
  --data-urlencode 'cursor=<next-cursor>' \
  --data-urlencode 'limit=100'
```

Events contain a public change ID, resource type and stable ID, operation,
optional revision/hash, source device, client-facing snapshot, and server
timestamp. The internal numeric sequence is not an API field. Cursors are
signed and account-bound; malformed, modified, or cross-account cursors return
`400 sync_cursor_invalid`. An empty page still returns a cursor for the next
poll.

Library creates, new content revisions, and completed assets append an event in
the same PostgreSQL transaction as the authoritative write. Identical content
retries do not append duplicates. Delete events and conflict-copy handling are
following slices.

### Idempotent synchronization commits

`POST /api/v1/sync/commit` currently writes complete JSON content for existing
notebooks, pages, and infinite canvases. First obtain and persist a cursor from
`GET /sync/changes`, then submit a batch:

```bash
curl -X POST 'http://127.0.0.1:8000/api/v1/sync/commit' \
  -H 'Authorization: Bearer <access-token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "deviceId": "<device-id-from-login>",
    "idempotencyKey": "<new-stable-key-for-this-batch>",
    "baseCursor": "<last-safely-applied-cursor>",
    "operations": [{
      "operationId": "page-save-1",
      "operation": "upsert",
      "resourceType": "page",
      "resourceId": "<existing-page-id>",
      "baseRevision": 0,
      "content": {"schemaVersion": 1, "strokes": []}
    }]
  }'
```

The whole batch uses one PostgreSQL transaction. If any resource is missing or
has a different current Revision, no operation in the batch is persisted. A
successful response contains one result per operation, including the server
Revision, content hash, whether content changed, and the new cursor.

Retries must send exactly the same body with the same `idempotencyKey`. The key
is scoped to the authenticated account and device. An exact retry returns the
stored result with `replayed: true` without creating another Revision or change
event; reusing the key for different input returns
`409 sync_idempotency_key_reused`. A stale but valid account cursor is accepted
so an offline device can submit work, while every `baseRevision` still prevents
silent overwrite. Invalid or account-mismatched cursors return `400`; cursors
ahead of account state return `409`.

This route does not yet create locally new resources and does not accept delete
operations. Those require the later metadata, tombstone, and conflict-copy
protocol slices.

### Safe asset cleanup

Asset cleanup is an explicit maintenance command; it does not run when the API
starts. From `server/`, preview the current work without changing PostgreSQL or
MinIO:

```bash
uv run python -m inknest_server.maintenance.cleanup_assets
```

The JSON output reports expired sessions, eligible staging objects, discovered
and eligible orphan objects, protected objects, deletions, and failures. After
reviewing the preview, apply eligible changes explicitly:

```bash
uv run python -m inknest_server.maintenance.cleanup_assets --execute
```

`--execute` is a routine maintenance operation but can physically delete
unreferenced MinIO objects. The safety rules are:

- pending uploads expire after 24 hours and retain staging bytes for another
  24 hours;
- cancelled uploads and completed-upload staging residue wait 1 hour;
- final notebook objects without an `assets.object_key` reference enter
  `asset_gc_candidates` for a 7-day quarantine;
- every candidate is checked again immediately before deletion, and a newly
  referenced object becomes `protected` instead;
- referenced ready assets are never selected, object keys must match the
  server-owned layout, and each run changes at most 100 records per category;
- upload rows and GC audit rows are retained. Failures record an attempt count
  and error type so the command can be retried safely.

Inspect `asset_uploads.staging_deleted_at`, `cleanup_attempts`, and
`last_cleanup_error`, plus rows in `asset_gc_candidates`, with Navicat or
pgAdmin. Inspect remaining bytes in the private bucket through MinIO Console.
If a run reports failures, do not manually remove referenced objects: correct
the database or MinIO connectivity problem and rerun dry-run, then `--execute`.

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
- `20260806_0006`: explicit staging object keys and completion timestamps for
  verification-driven promotion into ready `assets` references.
- `20260806_0007`: upload cleanup audit fields and quarantined
  `asset_gc_candidates` tracking for recoverable MinIO garbage collection.
- `20260806_0008`: append-only `sync_changes` with a PostgreSQL identity
  sequence, ownership fields, immutable payloads, and cursor indexes.
- `20260806_0009`: `sync_commits` request hashes and cached responses, uniquely
  scoped by account, authenticated device, and idempotency key.

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

There are no public library CRUD routes yet. The incremental feed, content-only
sync commit route for existing revisioned resources, and upload sessions are
the current library-related routes.
Inspect these tables in
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
not create duplicate history. Successful new revisions now append to
`sync_changes` and appear in the incremental feed. `/sync/commit` exposes this
same guarded write path as an atomic, idempotent batch for existing resources.

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
- `INKNEST_ASSET_DOWNLOAD_URL_MINUTES`: signed download URL lifetime, default 15.
- `INKNEST_MAX_ASSET_UPLOAD_BYTES`: per-asset limit, default 512 MiB.
- `INKNEST_ASSET_CLEANUP_PENDING_GRACE_HOURS`: extra staging retention after a
  pending session expires, default 24 hours.
- `INKNEST_ASSET_CLEANUP_STAGING_GRACE_HOURS`: wait after cancellation or
  completion before residual staging cleanup, default 1 hour.
- `INKNEST_ASSET_CLEANUP_ORPHAN_QUARANTINE_DAYS`: observation time before an
  unreferenced final object can be deleted, default 7 days.
- `INKNEST_ASSET_CLEANUP_BATCH_SIZE`: maximum records changed per cleanup
  category and run, default 100.
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
