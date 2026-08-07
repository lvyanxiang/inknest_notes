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
- `pendingOperations`: coalesced notebook, page, or infinite-canvas upserts.
- `inFlightBatch`: the exact `baseCursor`, idempotency Key, operations, and
  creation time for a request that may need byte-for-byte semantic retry.

The App must save local note content before enqueueing its sync operation. A
network failure leaves the in-flight batch unchanged. A successful whole-batch
response clears only that batch; edits made while it was uploading remain
pending and receive the successful server Revision as their next
`baseRevision`.

The Cursor returned by `POST /sync/commit` is not automatically treated as
locally applied. It may include another device's interleaved changes. Only the
Cursor from a `GET /sync/changes` page may be persisted, and only after every
change in that page has been safely applied.

Writes use a temporary JSON file followed by replacement. Invalid or unknown
state formats raise an error and are preserved for diagnosis rather than being
silently reset.

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
