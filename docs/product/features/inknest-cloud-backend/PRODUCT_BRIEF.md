# InkNest Cloud Backend Product Brief

- Status: Accepted
- Size: Large
- Updated: 2026-08-07
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

The App keeps accounts optional and the local library available before, during,
and after authentication. It stores the current access/refresh session in
platform secure storage, refreshes access centrally before or after an
authentication failure, and clears only cloud credentials on sign-out. Network
transport uses one project-owned Dio client so pages never handle tokens or raw
HTTP responses directly.

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

### Account session flow

- The library header exposes one Account entry without replacing the local
  library as the startup destination.
- Signed-out users can sign in or create an account with email/password. A
  successful response is committed to secure storage before the UI reports the
  user as signed in.
- App restart restores the stored identity immediately. An expired access token
  is refreshed centrally; concurrent authenticated requests share one refresh.
- A rejected refresh clears the unusable cloud session and asks the user to
  sign in again. A temporary network failure leaves local notes available and
  does not delete credentials or local data.
- Sign-out attempts server revocation and always removes the local session. It
  never deletes notebooks, folders, pages, or assets from the device.

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
- The Flutter API boundary parses the complete bootstrap snapshot before any
  local mutation. Duplicate IDs, count mismatches, invalid resource fields, or
  unknown parent notebook references reject the snapshot; unknown structured
  coordinate-space versions remain intact for a later compatibility decision.
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
- The planning layer itself performs no writes. Transfer slices consume the
  plan separately; shared Revision comparison, progress UI, and failure
  recovery remain later checklist items.
- The signed-in App now presents this plan. A pure cloud-only new device can
  confirm the completed verified restore path and refresh the shelf after
  success. A local-only device can upload its complete supported library and
  verified attachments, then save the refreshed bootstrap Cursor. A mixed
  library can now confirm Merge: shared structures and attachments must match
  exactly, while shared notebook/page/canvas content is submitted with an
  unknown base Revision so the server can return unchanged by Content Hash or
  preserve a notebook/page conflict. Unsupported structural, attachment, or
  canvas-content conflicts stop safely instead of guessing an overwrite.

### Library structure and JSON content transfer foundation

- Bootstrap includes complete active folder, notebook, page, and
  infinite-canvas snapshots in addition to stable-ID inventories, allowing a
  later App slice to stage cloud-only structure and JSON content without
  another lookup.
- `POST /api/v1/sync/merge/commit` accepts atomic, account-scoped creation of
  local-only folders, notebooks, pages, and infinite canvases. It retains client
  stable IDs, creates parents before children, and assigns initial server-owned
  Revisions and Content Hashes to page/canvas JSON.
- Exact retries share the existing account/device idempotency mechanism and
  replay the stored response. A stable ID already holding different metadata
  or content, an occupied placement, or an incompatible notebook layout
  produces an explicit error and rolls back every operation in the batch.
- Asset bytes use the separate verified transfer contract below. The App does
  stage cloud-only snapshots and atomically apply them only after every asset
  passes metadata, byte-size, and SHA-256 verification. The overall
  upload/download acceptance criterion remains incomplete until local-only
  upload and shared-Revision orchestration are wired into the first-sign-in
  flow.

### Ready asset transfer foundation

- Bootstrap includes account-scoped metadata for ready PDF, image, and audio
  assets attached to active notebooks. Pending, cancelled, expired, or failed
  upload sessions never appear as restorable assets.
- The snapshot exposes stable asset/notebook IDs, kind, original filename,
  validated notebook-relative path, media type, byte size, and SHA-256. It
  never exposes an internal MinIO object key or a reusable signed URL. Paths
  are unique inside one account/notebook and reject absolute/traversal input so
  restore never guesses a destination or writes outside the notebook.
- Local-only bytes use the existing retryable upload-session flow and become
  visible only after MinIO size, media type, and SHA-256 verification succeeds.
  Cloud-only bytes use the stable asset ID to request a short-lived download
  URL, after which the App must verify size and SHA-256 before local use.
- Flutter now requests a fresh signed URL per asset, downloads into disposable
  staging, verifies the signed response against bootstrap metadata plus the
  actual size and SHA-256, and rolls back every new directory/index mutation if
  application fails. Pure cloud-only restores persist the bootstrap Cursor
  after success; mixed libraries deliberately keep it unapplied until upload
  and shared-Revision work finishes.

### Incremental pull application contract

- A signed-in device with an applied Cursor requests every available
  `/sync/changes` page before changing local files. The App does not advance
  the Cursor merely because the transport request succeeded.
- The first application slice restores additive cloud-only folders/notebooks
  through the existing staged bootstrap path, including verified PDF, image,
  and audio assets. All referenced roots must be represented by the downloaded
  change range so a concurrent later bootstrap snapshot is not applied early.
- Existing-resource updates, deletes, conflicts, Tombstones, and any local
  pending queue stop before mutation and leave the original Cursor unchanged.
  They require the next Revision-aware push/reconciliation slice; the App does
  not use unconditional last-writer-wins replacement.
- On session restore, an initialized device attempts this pull before showing
  first-sign-in Merge again. Successful additive downloads refresh the library;
  offline or blocked reconciliation leaves local notes available.

## Acceptance Criteria

- [x] A user can register, sign in, refresh a session, sign out, and revoke a
  device without exposing another user's data.
- [x] A Flutter user can register/sign in from the library Account entry,
  restart the App with the session restored from secure storage, and sign out
  without changing the local library.
- [x] Authenticated Flutter requests attach the access token centrally and
  retry once after one shared refresh; a rejected refresh returns to signed-out
  state without logging token or response-body secrets.
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
- [x] Incremental pull can add a new cloud-only notebook and its verified
  content without replacing an existing local resource, and advances the
  Cursor only after the complete additive range is applied.
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
  conflict recovery flow. Account registration/sign-in/sign-out, visible
  detection, deterministic preview, offline/retry feedback, pure cloud-only
  restore, local-only upload, and safely gated mixed-library execution are
  implemented. Conflict list/detail UI remains a later slice.
- Implementation status: Phase 4 incremental synchronization is complete and
  Phase 5 library-presence detection, Merge planning, and server-side transfer
  contracts through page/infinite-canvas JSON and ready asset bytes are
  delivered in the implementation plan. Flutter now also has Dio-backed typed
  transport, platform-secure session persistence, shared automatic token
  refresh, Account UI, full-snapshot parsing, verified attachment downloads,
  rollback-safe cloud-only bootstrap application. The signed-in library now
  invokes that path through a visible confirmation flow and refreshes restored
  notebooks immediately. Local-only structure/content upload now calls Merge
  Commit; referenced assets use presigned PUT plus server-side size/SHA-256
  verification, and notebook content retains recording/outline/bookmark data.
  Shared-ID reconciliation now calls the typed incremental commit contract and
  uses server Revision/Content Hash outcomes before transferring either side's
  independent resources. Structural metadata, attachment differences, and
  divergent infinite-canvas content remain blocked pending explicit recovery
  support.
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
  Structure/content-transfer tests cover exact replay, parent dependency
  ordering, conflicting stable-ID rollback, full bootstrap snapshots, initial
  Revision/Content Hash creation, same-content retry, and real PostgreSQL
  duplicate prevention for pages and infinite canvases. PostgreSQL migration
  `20260806_0012` is current and adds restorable, unique notebook-relative
  asset paths. A shared bootstrap JSON fixture is parsed by
  both the Flutter DTOs and the FastAPI response schema so client/server field
  drift fails in tests. The complete backend run passes 49
  non-integration tests and 15 PostgreSQL/MinIO integration tests, including
  ready-only bootstrap visibility and real PDF/image/audio byte round trips;
  the complete Flutter suite passes with 195 tests. The mixed-library slice is
  additionally covered by 11 focused backend sync-change tests; staging tests
  cover verified success, corrupt downloads, and mid-apply rollback, and
  static analysis passes.
