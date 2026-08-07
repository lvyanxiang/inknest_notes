# InkNest Notes Storage

Local data is stored as readable JSON under the app documents directory.

```text
notebooks/
  index.json
  notebook-id/
    pages/
      page-1.json
      page-2.json
    assets/
      imported.pdf
      pdfs/
        source-name.pdf
        source-name-2.pdf
sync/
  user-id/
    device-id/
      state.json
      conflicts.json
      tombstones.json
```

## `notebooks/index.json`

Stores notebook metadata:

- `id`
- `title`
- `createdAt`
- `updatedAt`
- `pageIds`

## `notebooks/<id>/pages/<page-id>.json`

Stores one notebook page:

- `id`
- `width`
- `height`
- `pdfBackground`
- `strokes`

`pdfBackground` is optional and stores:

- `assetPath`
- `pageNumber`

The library-level single-PDF import keeps its source at
`assets/imported.pdf` for backward compatibility. PDFs appended from an open
notebook are copied to `assets/pdfs/`; sanitized same-name collisions receive
numeric suffixes so every imported document remains independent.

Each stroke stores:

- `id`
- `tool`
- `color`
- `width`
- `points`

Each point stores:

- `x`
- `y`
- `pressure`
- `time`

## `sync/<user-id>/<device-id>/state.json`

Synchronization state is a versioned sidecar and is not embedded in notebook
JSON. Separating it prevents account/session changes from rewriting local note
content and allows two devices or accounts to maintain independent progress.

The file stores:

- `formatVersion`: currently `1`.
- `lastAppliedCursor`: the opaque server Cursor for the last pull page that was
  completely and safely applied locally.
- `pendingOperations`: coalesced notebook, page, or infinite-canvas upserts,
  plus mapped whole-notebook deletes.
- `inFlightBatch`: the exact `baseCursor`, idempotency Key, operations, and
  creation time for a request that may need byte-for-byte semantic retry.

The App must save local note content before enqueueing its sync operation. A
network failure leaves the in-flight batch unchanged. A successful whole-batch
response clears only that batch; edits made while it was uploading remain
pending and receive the successful server Revision as their next
`baseRevision`.

A whole-notebook delete replaces any unsent upsert for the same mapped resource
while preserving its oldest `baseRevision` and operation ID. Its serialized
operation uses `operation: delete` and omits `content`. The shelf entry is
removed only after this queue write succeeds; a queue failure restores the
original index entry. Online deletion immediately attempts push/pull, while an
offline deletion remains durable for startup retry.

The Cursor returned by `POST /sync/commit` is not automatically treated as
locally applied. It may include another device's interleaved changes. Only the
Cursor from a `GET /sync/changes` page may be persisted, and only after every
change in that page has been safely applied.

For a new-device bootstrap, `lastAppliedCursor` is also the final handoff
marker. Downloaded files and `resources.json` must be durable first; only then
may the bootstrap Cursor be written. If mapping persistence fails after content
application, the Cursor remains absent, so restart cannot falsely enter normal
incremental synchronization with incomplete mappings.

Writes use a temporary JSON file followed by replacement. Invalid or unknown
state formats raise an error and are preserved for diagnosis rather than being
silently reset.

## `sync/<user-id>/<device-id>/conflicts.json`

The versioned conflict sidecar stores the complete typed snapshots received in
`conflict` upsert change events, including the original and reserved-copy IDs,
display label, base/current Revisions, both content snapshots and hashes,
source device, status, resolution metadata, and creation time. The App derives
its pending list from records whose status is `pending`; resolved records remain
durable history but no longer appear in that list.

A conflict-only change range is written atomically before the pull Cursor is
advanced. On restart, the list is loaded before requesting newer changes, so a
pending badge cannot disappear merely because the App closed. Mixed conflict
and content ranges are acknowledged only after the resource update/addition,
resolved conflict record, resource map, and final Cursor all have a safe
application path. Retrying a partially applied Keep Both page addition accepts
the same final-position page and rejects a colliding ID with different content.

## `sync/<user-id>/<device-id>/tombstones.json`

The versioned Tombstone sidecar stores typed soft-delete snapshots and their
active/restored state. The App derives Recently Deleted from active notebook and
page records, sorted by deletion time; unsupported standalone-canvas recovery
does not appear as an action. Restored records remain in the sidecar as durable
history but disappear from the active list.

Tombstone changes are written atomically before the pull Cursor advances. A
restore request does not optimistically remove its row: the App first pulls the
resulting resource upsert and restored Tombstone, applies the notebook or safe
page locally, updates mappings, and only then advances the Cursor and refreshes
Recently Deleted. Failures keep the active record visible for retry.

## `sync/<user-id>/<device-id>/resources.json`

The versioned resource map connects local repository keys to account-global
cloud IDs. Each entry stores its resource type, remote ID, latest server
Revision, and Content Hash. `cloudAssetKeys` records notebook-relative assets
verified by the latest applied bootstrap. Paged notes use a notebook-qualified
local page key because legacy local files may reuse `page-1` in different
notebooks.

The map is rebuilt only from a verified bootstrap/merge result. Normal page
saves consult it before entering `state.json`; an unmapped save remains local
and does not guess a cloud ID. Successful `/sync/commit` results update the
mapped Revision and hash before the frozen in-flight batch is cleared.
Notebook and canvas content that references a page or attachment is queued only
when that reference resolves through this verified map.

## `sync/<user-id>/<device-id>/deleted/<tombstone-id>/`

When an initialized device safely applies a remote whole-notebook deletion, it
moves the complete local notebook directory into this recovery area before
removing the notebook from `notebooks/index.json`. `local-notebook.json` keeps
the former shelf metadata, `tombstone.json` keeps the validated server
Tombstone, and `notebook/` contains the untouched local files and assets.

The move and index replacement roll back together on ordinary failures. If the
process stops after the move but before Cursor persistence, retry recognizes the
same recovery directory and completes idempotently. Page and infinite-canvas
deletions are not stored here until the local repository can represent them
without leaving an invalid notebook.

For a safe remote trailing-page deletion, the same Tombstone directory stores
`page.json`, `location.json`, and `tombstone.json`. The first file is the exact
local page, the second records notebook ID, page ID, and former position, and
the third records the validated server Tombstone. The page is removed from the
notebook index only after the recovery files can be created; failures restore
the original index and page file.
