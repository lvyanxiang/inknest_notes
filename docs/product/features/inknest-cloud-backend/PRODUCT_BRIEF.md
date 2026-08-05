# InkNest Cloud Backend Product Brief

- Status: Accepted
- Size: Large
- Updated: 2026-08-05
- Roadmap link: `docs/development/ROADMAP.md#milestone-8-sync-and-backup-paused`

## Problem

InkNest is currently a local-first Flutter application. Users can create rich
notebooks containing page JSON, handwriting, text, shapes, PDF backgrounds,
images, and audio, but there is no account-backed recovery or cross-device
protection. Signing in or restoring from cloud data must never silently delete
or overwrite notebooks that already exist on the device.

## Recommended Outcome

Add a custom Python service inside the existing repository and use PostgreSQL
for authoritative metadata and revisions, plus self-hosted MinIO for binary
objects. Keep the Flutter app local-first: local writes remain immediately
available, while the service provides account-backed backup, incremental sync,
new-device restore, version history, and conservative conflict recovery.

The first synchronization version operates at folder, notebook metadata, page,
infinite-canvas document, and asset granularity. It does not attempt
stroke-level merging or real-time collaboration.

## Scope

- In scope:
  - InkNest accounts, sessions, and registered devices.
  - PostgreSQL-backed folders, notebooks, pages, revisions, tombstones,
    synchronization changes, conflicts, backups, and storage usage.
  - MinIO-backed PDF, image, audio, thumbnail, export, and backup objects.
  - Incremental push/pull synchronization with opaque cursors and idempotent
    commits.
  - Optimistic revision checks and explicit conflict copies.
  - Default merge of pre-existing local notebooks with cloud notebooks.
  - Manual backup/restore followed by automatic background sync.
  - A same-repository `server/` Python project and shared API contract.
- Non-goals:
  - Stroke-level CRDT or operational transformation.
  - Multi-user live collaboration, team spaces, comments, or presence.
  - OCR, transcription, AI retrieval, or Elasticsearch in the first version.
  - A full Web editor, subscription checkout, or production multi-region
    storage cluster.
  - Moving the existing Flutter project from the repository root.

## User Flow

1. The user continues using InkNest locally without requiring an account.
2. When the user signs in, InkNest compares the local library with the cloud
   library and recommends Merge.
3. Local-only notebooks upload, cloud-only notebooks download, and unrelated
   IDs remain separate even when titles match.
4. When the same object changed on both sides, InkNest preserves both outcomes
   and labels a conflict copy instead of overwriting either side.
5. On a new device, the user signs in and restores cloud notebooks, assets,
   folder organization, and supported history.
6. An explicit replace-local action, if added later, requires a second
   confirmation and a recoverable backup before replacement.

## Acceptance Criteria

- [ ] A user can register, sign in, refresh a session, sign out, and revoke a
  device without exposing another user's data.
- [ ] A device can upload and download notebook metadata, pages, infinite
  canvases, and referenced assets without requiring a full-library transfer on
  every sync.
- [ ] Retrying the same synchronization commit does not duplicate pages,
  assets, conflicts, or change events.
- [ ] Signing in on a device with local notebooks defaults to merge and does
  not delete local-only content.
- [ ] Concurrent edits to the same revision produce an explicit page- or
  notebook-level conflict copy; neither edit is silently discarded.
- [ ] Delete-versus-edit conflicts preserve the edited content and retain a
  tombstone for explicit recovery.
- [ ] Interrupted asset uploads can be retried, and completed objects are
  verified by size and SHA-256 before becoming available.
- [ ] A new device can restore notebook structure and all referenced PDF,
  image, and audio assets.
- [ ] Existing local notebooks remain readable and editable when the service
  is offline or unavailable.
- [ ] Backup and restore failures leave the pre-existing local library intact.

## Alternatives And Tradeoffs

- Option: Separate Flutter and Python repositories.
  - Why not now: Cross-client schema and synchronization changes would require
    coordinating two repositories and two Codex workspaces. A same-repository
    service provides simpler atomic changes without restructuring the Flutter
    tree.
- Option: Move Flutter into `apps/mobile` and Python into `services/api`.
  - Why not now: This is aesthetically cleaner but creates a large, risky path
    migration with little immediate user value. The repository can evolve to
    that layout later if more clients are added.
- Option: Supabase for database, auth, and storage.
  - Why not now: It reduces initial operations but weakens the explicit Python
    backend scope and adds platform dependency. The selected stack keeps the
    service portable and locally demonstrable.
- Option: Store assets directly in PostgreSQL.
  - Why not now: Large PDFs, images, audio, and versioned backups would inflate
    database backups and make file transfer and retry behavior more expensive.
- Option: Elasticsearch from the first release.
  - Why not now: Search is not required to prove safe synchronization and can
    begin with PostgreSQL before a separate rebuildable index is justified.

## Dependencies And Risks

- Product or technical dependency:
  - A versioned `.inknestbackup` archive and shared serialization contract.
  - Sync metadata on local models or a sidecar sync-state store.
  - Docker-compatible development environment for PostgreSQL and MinIO.
  - A UI/UX specification before sign-in, merge, sync-status, conflict, or
    restore screens are implemented.
- Data, privacy, performance, or migration risk:
  - Incorrect revision or tombstone semantics can cause data loss.
  - Asset metadata and MinIO objects can drift without transactional finalize
    and garbage-collection rules.
  - Existing coordinate-space write protection must remain enforced during
    upload, restore, and conflict-copy creation.
  - MinIO's license and single-node durability are acceptable for development
    and demonstration but require review before a closed-source production
    deployment.

## Open Decisions

- Choose the first production hosting region and whether production remains on
  MinIO or switches behind the same storage interface to OSS/S3.
- Choose email delivery and the first sign-in method before account UI work.
- Set cloud quota and version-retention limits before a public launch.

## Delivery

- UI/UX spec: Required before Flutter account, merge, sync, conflict, and
  restore integration; not part of this backend planning task.
- Implementation status: Planned in
  `docs/development/BACKEND_IMPLEMENTATION_PLAN.md`.
- Verification: Documentation review and `git diff --check` for this planning
  delivery; code verification begins with the server scaffold milestone.
