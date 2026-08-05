---
name: inknest-backend
description: Deliver the InkNest Notes Python backend from the repository's accepted backend plan. Use whenever Codex is asked to start, continue, implement, scaffold, test, review, or mark progress on the InkNest server, FastAPI API, PostgreSQL schema or migrations, MinIO storage, accounts and devices, backup/restore, cloud sync, revisions, tombstones, conflicts, or backend deployment.
---

# InkNest Backend

Deliver the backend as small, verified slices while preserving InkNest's
local-first data-safety rules and durable project records.

## Recover Context

Read these repository files completely before backend work:

1. `docs/development/STATUS.md`.
2. `docs/development/BACKEND_IMPLEMENTATION_PLAN.md`.
3. `docs/product/features/inknest-cloud-backend/PRODUCT_BRIEF.md`.
4. The Post-MVP 6 section of `docs/development/POST_MVP_ROADMAP.md`.
5. Files directly involved in the selected slice.

Also use `$inknest-project` and `$inknest-product-manager` for project state and
material requirement decisions. Before implementing visible sign-in, merge,
sync-status, conflict, backup, or restore behavior, use `$inknest-ui-ux` and
create or update the required UI/UX specification.

Do not read or modify `docs/academic/` unless the user explicitly requests
academic-document maintenance.

## Select The Delivery Slice

- Follow an explicitly requested phase or checklist item.
- When the user asks to start the service and `server/` does not exist, execute
  Section 14, "第一个可执行切片", from the implementation plan. Do not attempt
  every phase in one turn.
- When the user asks to continue without naming a phase, use `STATUS.md` and the
  plan checkboxes to select the first genuinely unfinished item in the active
  backend phase.
- When the user explicitly requests continuous delivery, complete phases in
  order, validating and updating records after each phase.
- Do not infer Elasticsearch, Redis, Celery, Kubernetes, collaboration, OCR,
  AI, subscription checkout, or production deployment from the core backend
  plan.

State the selected slice and key assumptions in commentary before editing.

## Preserve The Architecture

- Keep the Flutter project at the repository root.
- Add backend code under `server/`; keep Python dependencies inside
  `server/pyproject.toml`.
- Keep shared orchestration such as `compose.yaml` at the repository root.
- Use FastAPI, PostgreSQL, SQLAlchemy, Alembic, and a MinIO-backed storage
  adapter unless an accepted decision changes the stack.
- Store authoritative business metadata, revisions, cursors, tombstones, and
  conflict relationships in PostgreSQL.
- Store PDF, image, audio, thumbnail, export, and backup bytes in MinIO. Store
  only their metadata and object keys in PostgreSQL.
- Keep object storage behind an interface that can later target OSS or S3.
- Keep the app local-first; the service must never become a prerequisite for
  local writing or saving.

## Enforce Data-Safety Rules

- Default first sign-in and restore to Merge.
- Never identify a notebook by title; use stable IDs.
- Never silently overwrite uncertain or concurrent local content.
- Create explicit conflict copies when both sides changed from a common
  revision or ancestry is unclear.
- Preserve edited content in delete-versus-edit conflicts.
- Use server-owned revisions, opaque cursors, tombstones, content hashes, and
  idempotency keys as defined by the plan.
- Verify asset size and SHA-256 before marking an upload ready.
- Restore into temporary storage, verify the manifest and checksums, then merge
  or atomically replace only when the selected flow explicitly permits it.
- Preserve unknown and protected `coordinateSpaceVersion` content without
  server-side rewriting.

Stop and request direction before changing conflict semantics, destructive
migration behavior, retention, encryption scope, authentication strategy,
production topology, or the accepted local/cloud merge policy.

## Implement

1. Inspect existing code and dirty worktree state; preserve unrelated user
   changes.
2. Define the smallest coherent change that satisfies the selected checklist
   item and its acceptance criteria.
3. Add migrations, models, services, API schemas, adapters, and tests together
   when the slice requires them.
4. Keep credentials out of source control. Add placeholders only to
   `.env.example` and document their purpose.
5. Keep API contracts explicit and versioned under `/api/v1`.
6. Prefer database transactions for authoritative state and finalize MinIO
   objects through recoverable state transitions; do not pretend the database
   and object store share one atomic transaction.
7. Make retries safe before adding background concurrency.

Do not mark plan work complete for scaffolding, TODOs, mocked success paths, or
unverified migrations.

## Teach The Manual Workflow

Treat the user as an experienced software learner who is new to Python backend
development. After changing backend code, explain how the same work would be
done without AI instead of reporting only the finished diff.

Read `references/python-backend-workflows.md` completely whenever the selected
slice changes Python dependencies, application startup, FastAPI routes,
SQLAlchemy models, Alembic migrations, PostgreSQL, MinIO, or Compose. Tailor
the relevant workflow to the actual change; do not paste unrelated commands.

For every affected subsystem, include:

1. Its role and, when useful, the closest Node.js ecosystem analogy.
2. The source files a developer would normally edit and why.
3. Exact commands, including the directory from which to run them.
4. Which commands are one-time setup versus routine development commands.
5. The expected observable result and how to inspect it in Swagger, PostgreSQL,
   MinIO Console, logs, or tests.
6. A safe failure or rollback path. Label destructive or data-losing commands
   explicitly and never present them as routine cleanup.

When a database schema changes, always explain this sequence explicitly:

- Change or add the SQLAlchemy model.
- Make the model metadata discoverable by Alembic.
- Generate an Alembic revision; do not imply that changing a model updates the
  database automatically.
- Inspect both `upgrade()` and `downgrade()` before execution.
- Apply the migration, check `alembic current`, inspect the schema, and run the
  relevant tests.

Use `uv add` and `uv sync` rather than ad-hoc `pip install` commands. Keep the
host-versus-container address distinction explicit: host API development uses
`localhost`, while the containerized API uses Compose service names such as
`postgres` and `minio`. Update `server/README.md` whenever an operator or daily
development command changes.

Never assume that tracked `.env.example` credentials equal the user's ignored
local `.env` values. Use placeholders or commands that read container/local
environment variables, and do not print passwords, tokens, or MinIO secrets in
the handoff.

## Verify

Run checks proportional to the files changed:

- Python formatting, linting, type checks, and pytest commands defined by
  `server/pyproject.toml`.
- Alembic upgrade from an empty test database when migrations change.
- PostgreSQL and MinIO integration tests when persistence or storage changes.
- `docker compose config` and relevant health checks when orchestration changes.
- Flutter focused tests, then `flutter test` and `flutter analyze`, when client
  code changes.
- `git diff --check` for every delivery.

If required infrastructure cannot run, record the exact limitation and keep
the affected checklist item incomplete.

## Update Durable Records

After a meaningful verified slice:

1. Check only the actually completed items in
   `docs/development/BACKEND_IMPLEMENTATION_PLAN.md`.
2. Keep `docs/development/ROADMAP.md` and
   `docs/development/POST_MVP_ROADMAP.md` aligned when a roadmap task completes.
3. Update `docs/development/STATUS.md` with current backend phase, next task,
   decisions, and verification.
4. Update the backend Product Brief and `docs/product/PRODUCT_DECISIONS.md` only
   when an accepted product decision materially changes.

Do not replace detailed plan history with vague statements such as "backend
progressed".

## Hand Off

Report:

- The completed slice and user-visible or architectural outcome.
- Important files changed.
- Validation executed and any checks not run.
- A concise "without AI" workflow for reproducing the affected Python backend
  work, including commands, expected results, and safe recovery guidance.
- The exact next unchecked backend task.
- Any unresolved decision that must be made before continuing.
