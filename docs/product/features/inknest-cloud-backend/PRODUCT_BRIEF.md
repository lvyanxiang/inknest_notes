# InkNest Cloud Backend Product Brief

- Status: Accepted
- Size: Large
- Updated: 2026-08-06
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

For concurrent page/notebook edits, the accepted conservative behavior is to
leave the authoritative resource unchanged and persist both snapshots in a
pending conflict record with a stable reserved copy ID. The App will offer
Keep Original, Use Conflict Version, and Keep Both. Keep Both materializes the
reserved resource with `conflictOf` ancestry; retries reuse the same conflict.

For delete-versus-edit races, edited content wins automatically regardless of
arrival order. A normal delete is a reversible soft delete backed by a full
snapshot Tombstone; an explicit restore writes that snapshot as a new Revision.
The first slice sets no retention period and performs no physical cleanup.

## Scope

- In scope:
  - InkNest accounts, sessions, and registered devices.
  - Email/password as the first sign-in method, initially without mandatory
    email verification; short-lived JWT access tokens and rotated,
    server-revocable refresh tokens.
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
5. The user explicitly keeps the original, uses the conflicting version, or
   keeps both. A newer edit made after the conflict blocks stale replacement
   and leaves recovery data intact.
6. On a new device, the user signs in and restores cloud notebooks, assets,
   folder organization, and supported history.
7. An explicit replace-local action, if added later, requires a second
   confirmation and a recoverable backup before replacement.

### First-sign-in library detection contract

- Before any transfer, the App reads the local folder/notebook IDs and calls
  the authenticated, read-only `GET /api/v1/sync/bootstrap` endpoint for the
  current account's active cloud folder/notebook IDs.
- Folder and notebook identity is determined only by the persisted stable ID.
  Titles and folder names are display metadata and are never used to infer
  that two objects are the same.
- The four presence outcomes are empty, local only, cloud only, and local plus
  cloud. Every non-empty outcome continues through the same conservative Merge
  path; local plus cloud must be presented as `Merge (Recommended)`.
- This first bootstrap slice is an inventory check only. Its `baseCursor` is a
  hand-off point for a later full-bootstrap implementation and must not be
  persisted as the App's applied pull Cursor until all corresponding cloud
  snapshots have been downloaded, validated, and committed locally.
- Cancelling, going offline, receiving `401`, or receiving a server error makes
  no local mutations and leaves the existing local library usable.

### Default Merge planning contract

- The App converts the two stable-ID inventories into a deterministic plan
  before any network or local write begins.
- A local-only folder/notebook produces `uploadLocal`; a cloud-only
  folder/notebook produces `downloadCloud`; an ID present on both sides
  produces `reconcileShared` so a later slice can compare Revision and ancestry
  without guessing which side should win.
- The plan contains resource type and stable ID only. It has no title/name
  matching path and no delete, replace-local, or overwrite action.
- Actions are sorted by resource type, action, and ID so recreating a plan for
  retry produces the same order. Planning is pure and cannot mutate either
  library.
- This slice implements the plan only. Executing uploads/downloads, comparing
  shared Revision state, progress UI, and failure recovery remain separate
  checklist items.

## Acceptance Criteria

- [x] A user can register, sign in, refresh a session, sign out, and revoke a
  device without exposing another user's data.
- [ ] A device can upload and download notebook metadata, pages, infinite
  canvases, and referenced assets without requiring a full-library transfer on
  every sync.
- [x] Retrying the same synchronization commit does not duplicate pages,
  assets, conflicts, or change events.
- [ ] Signing in on a device with local notebooks defaults to merge and does
  not delete local-only content.
- [x] A signed-in device can detect empty/local-only/cloud-only/both library
  presence from stable folder/notebook IDs without transferring or modifying
  note content.
- [x] Concurrent edits to the same revision produce an explicit page- or
  notebook-level conflict copy; neither edit is silently discarded.
- [x] Delete-versus-edit conflicts preserve the edited content and retain a
  tombstone for explicit recovery.
- [ ] Interrupted asset uploads can be retried, and completed objects are
  verified by size and SHA-256 before becoming available.
- [ ] A new device can restore notebook structure and all referenced PDF,
  image, and audio assets.
- [x] Existing local notebooks remain readable and editable when the service
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
  - The server conflict contract is complete; Flutter still needs to consume
    conflict events and implement the specified recovery UI.
- Data, privacy, performance, or migration risk:
  - Incorrect revision or tombstone semantics can cause data loss.
  - Asset metadata and MinIO objects can drift without transactional finalize
    and garbage-collection rules.
    The delivered cleanup policy keeps referenced ready assets protected,
    gives expired pending uploads a 24-hour staging grace period, waits 1 hour
    for cancelled/completed staging residue, and quarantines unreferenced final
    objects for 7 days with a final database-reference check before deletion.
  - Existing coordinate-space write protection must remain enforced during
    upload, restore, and conflict-copy creation.
  - MinIO's license and single-node durability are acceptable for development
    and demonstration but require review before a closed-source production
    deployment.

## Open Decisions

- Choose the first production hosting region and whether production remains on
  MinIO or switches behind the same storage interface to OSS/S3.
- Choose the production email provider and verification-enforcement policy
  before public launch; initial account development does not require email
  verification.
- Set cloud quota and version-retention limits before a public launch.

## Delivery

- UI/UX spec: `UI_UX_SPEC.md` defines first-sign-in detection plus the future
  conflict recovery flow. Detection and the deterministic default-Merge plan
  are implemented; visible sign-in/merge screens and transfer progress remain
  later slices.
- Implementation status: Phase 4 incremental synchronization is complete and
  Phase 5 library-presence detection plus Merge planning are delivered in
  `docs/development/BACKEND_IMPLEMENTATION_PLAN.md`.
- Verification: Backend tests cover authentication, account isolation,
  revisioned content, asset transfer, cursors, atomic/idempotent commits, page
  and notebook conflicts, all resolution choices, soft delete/restore, both
  delete-edit arrival orders, failed-batch rollback, offline edits to separate
  pages, response-loss replay, and a real PostgreSQL race that always preserves
  the edit. The Flutter queue preserves offline/in-flight work across restart,
  rejects duplicate or partial operation results, and never advances its pull
  Cursor from a commit response. Bootstrap tests cover empty and populated
  accounts, stable-ID comparison, duplicate/inconsistent response rejection,
  local archived/folder/root discovery, and real PostgreSQL account isolation.
  Merge-plan tests cover stable-ID-only upload/download/shared actions,
  deterministic retry ordering, empty libraries, and corrupt local IDs.
  PostgreSQL migration `20260806_0011` remains current; this read-only slice
  requires no schema migration.
