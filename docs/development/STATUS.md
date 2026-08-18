# InkNest Notes Status

## Current

- Milestone: Local content recognition now uses ML Kit across iOS and Android
  for PDF/image OCR and selected-stroke Smart Ink recognition.
- Next task: Revalidate representative Chinese/English handwriting, scanned PDFs,
  and inserted images on physical iOS and Android devices, including first-use
  model download, rotation, memory, accuracy, and latency.
- Last completed: Smart Ink redraw now treats the original painted/lasso bounds
  as a fixed container. It measures padded raster glyph ink, preserves explicit
  lines without auto-wrap, uniformly contains every generated stroke, and no
  longer inflates the source selection.

### Licensing follow-up before public release or commercial use

- [ ] Replace the provisional copyright-holder name `Lv` in `LICENSING.md`,
  `CLA.md`, `TRADEMARKS.md`, `COMMERCIAL-LICENSE.md`, and
  `docs/academic/README.md` with the chosen legal identity: full personal legal
  name or the company that actually owns the copyright. Keep one spelling in
  Chinese and English records and confirm that employment/school agreements do
  not assign the work elsewhere.
- [ ] Confirm the permanent licensing contact address. Replace
  `2256334253@qq.com` if a dedicated domain mailbox will be used, and keep that
  address consistent in commercial and trademark notices.
- [ ] Complete a name and trademark clearance search for `InkNest` and
  `InkNest Notes` in intended App Store, domain, package, and target-market
  trademark classes; rename before release if clearance is unfavorable.
- [ ] Confirm ownership and provenance of the final logo, application icon,
  screenshots, illustrations, fonts, and store assets. Keep third-party items
  under their own notices and decide whether to register the cleared word/logo
  marks.
- [ ] Decide how individual and organizational contributors accept the CLA.
  Configure a durable CLA check/record for pull requests and require a
  separately signed organizational CLA for substantial company-owned work if
  counsel recommends it. Do not accept substantive external contributions
  until this process is operational.
- [ ] Before operating a modified public InkNest server, add a prominent,
  version-matched source-code link for network users and retain the exact
  corresponding source for every deployed version as required by AGPL section
  13.
- [ ] Before an App Store, Play Store, commercial, or customer release, have
  counsel review AGPL/store compatibility, the CLA, trademark policy, and the
  commercial-license agreement for the relevant jurisdiction. Regenerate the
  dependency and asset license inventory for that exact release.

## Decisions

- Use `docs/development/ROADMAP.md` as the main checklist for project execution.
- Use this file as the short resume point for future sessions.
- Keep the first product direction iPadOS/iOS-first, handwriting-first, and paged-notebook based.
- Clip every infinite-canvas visual layer as one viewport while preserving the
  complete world-coordinate document and native route transition.
- Use `AGPL-3.0-only` for InkNest software, accept contributions only under the
  repository CLA so separate commercial licensing remains possible, apply
  CC BY-SA 4.0 only to ordinary project documentation, and keep InkNest
  branding plus `docs/academic/` outside those grants.
- Treat the current `Lv` copyright identity and `2256334253@qq.com` contact as
  provisional release metadata, not a final legal-identity decision. Complete
  the licensing follow-up checklist before public binary/commercial release or
  accepting substantive external contributions.
- Use project skill `.codex/skills/inknest-project` to recover context without rereading the whole repo.
- Use project skill `.codex/skills/inknest-backend` to start, continue, verify,
  and record Python/PostgreSQL/MinIO backend delivery from the accepted plan.
- Apply Alembic migrations as an explicit development/deployment step, then
  make each API process perform a read-only database-Head versus code-Head
  check before serving requests. Never let every API replica race to migrate
  the database during application startup.
- Use `$inknest-project` as the single entry for new or changed requirements: always run `$inknest-product-manager`, and also run `$inknest-ui-ux` when visible or interactive behavior changes.
- Keep small requirement analysis in the task response; create `PRODUCT_BRIEF.md` and `UI_UX_SPEC.md` under `docs/product/features/<feature-slug>/` for medium or large work, and record only accepted durable decisions in the global product/design logs.
- Treat `/sync/bootstrap`'s current `baseCursor` as a bootstrap hand-off point,
  not an applied pull Cursor; save it only after a later full-bootstrap flow
  has downloaded, verified, and atomically applied the matching cloud state.
- Configure the Flutter service origin from a gitignored `.env.flutter` via
  `--dart-define-from-file=.env.flutter`, or a one-off
  `--dart-define=INKNEST_API_BASE_URL=<origin>`. The committed default remains
  `http://127.0.0.1:8000`; keep versioned `/api/v1` paths inside the API client
  instead of duplicating them at call sites.
- Keep Dio, token attachment, one-time 401 retry, refresh rotation, and safe API
  error mapping behind `InkNestApiClient`; widgets and repositories never
  receive or log raw tokens.
- Store account sessions with `flutter_secure_storage` (Keychain on Apple
  platforms and encrypted platform storage elsewhere). Authentication remains
  optional, and local sign-out never deletes the notebook repository.
- Store a separate random installation ID in platform secure storage. Sign-out
  clears only the account session; repeated login reuses the matching server
  device. A reset identifier is a valid new device and must rebuild sync
  mappings without changing already-restored cloud resource IDs.
- Treat initialized-device local-only roots as pending cloud creation even when
  no ordinary mapped mutation exists. Upload them before incremental pull,
  rebuild mappings, and requeue current content to cover edits made during the
  creation request; login must repair missed local triggers.
- Parse bootstrap payloads strictly and preserve unknown structured
  `coordinateSpaceVersion` values without rewriting them. A malformed or
  internally inconsistent snapshot fails before local writes begin.
- Build first-sign-in Merge actions deterministically from resource type,
  action kind, and stable ID. Local-only resources upload, cloud-only resources
  download, and shared IDs enter Revision/ancestry reconciliation; planning
  itself must never create a delete or replace-local action.
- Run first-sign-in detection after an authenticated session becomes active.
  Pure cloud-only libraries may execute the completed verified restore path;
  local-only and mixed libraries show their upload/download/shared counts but
  keep execution unavailable until upload and shared-Revision orchestration
  can complete the whole plan safely.
- Treat imported attachments as immutable first-bootstrap objects. Derive a
  deterministic account-local asset ID from notebook ID plus relative path,
  recompute size/SHA-256 immediately before upload, use a retryable presigned
  session, and accept success only after bootstrap returns matching metadata.
- Keep first-merge metadata creation separate from ordinary Revision content
  commits. The API creates folders before dependent notebooks, retains request
  result order, shares the account/device idempotency namespace, and treats its
  returned Cursor as unapplied until local download staging succeeds.
- During first merge, create dependencies in folder → notebook → page/canvas
  order while preserving response order. Page and infinite-canvas JSON enters
  cloud state at server-owned Revision 1; occupied IDs/placements, missing
  parents, or incompatible notebook layouts never partially commit a batch.
- When no implementation task is selected, product analysis may recommend candidates but must not automatically start Post-MVP 6-9 or infer work from plain roadmap bullets.
- Keep normal `$inknest-project` work focused on code, roadmap, and product implementation; do not automatically update task book or opening report during development tasks.
- Use `$inknest-academic-docs` for `docs/academic/GRADUATION_TASK_BOOK.md`, `docs/academic/OPENING_REPORT.md`, academic writing requirements, graduation schedule, and formal reference maintenance.
- Follow `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md` before updating academic graduation documents through `$inknest-academic-docs`.
- Graduation topic is `基于 Flutter 与 Python 的跨平台数字笔记系统的设计与实现`; keep current Flutter frontend docs here and add Python project details later.
- Keep the first app shell dependency-free; add state management and routing when notebook creation/navigation needs them.
- Use an in-memory notebook repository until local persistence begins.
- Keep first handwriting state in editor memory until local persistence begins.
- Use the first eraser as whole-stroke erasing by proximity; partial stroke splitting can come later.
- Store notebook metadata and page strokes as readable JSON under the app documents directory.
- Store page order on `Notebook.pageIds`; each page is saved as `pages/<page-id>.json`.
- Use `file_picker` for PDF selection and `pdfrx` for iOS/iPadOS PDF rendering.
- Use `pdfrx` selectable text first and ML Kit Text Recognition only as a
  scanned-page fallback on both iOS and Android. Keep OCR output in a versioned,
  fingerprinted `derived/recognition` sidecar outside notebook JSON and sync.
- Keep iOS at deployment target 15.5 for ML Kit. Keep Android on AGP 8.13 while
  required plugins still apply the legacy Kotlin Gradle plugin; reassess AGP 9
  Built-in Kotlin after those plugins migrate.
- Use the `pdf` package for PDF export, `image` for rendered PDF background encoding, and `file_picker.saveFile` for the first save/share action.
- Exported annotated PDFs rasterize imported PDF backgrounds and overlay editable strokes as vector paths in the generated output.
- Pause sync and backup until the editor, PDF, and library workflows are more polished.
- When backend implementation begins, keep Flutter at the repository root and
  add a same-repository `server/` Python project; use PostgreSQL for
  authoritative metadata and revisions, MinIO for binary objects, and a
  storage adapter that can later target OSS/S3.
- Keep cloud sync local-first: first sign-in defaults to merging local and
  cloud libraries, uncertain or concurrent edits create recoverable conflict
  copies, and no restore path silently overwrites local notes.
- Keep sync Cursors server-owned, signed, account-bound, and opaque to clients;
  the App persists a page Cursor only after applying the complete page locally.
- Keep `/sync/commit` batches atomic and scope idempotency keys to one account
  and authenticated device. A stale account Cursor may submit work, but every
  content operation must pass its resource Revision guard; a Cursor ahead of
  the account state is rejected. The current route updates existing revisioned
  resources, soft-deletes existing revisioned resources, and creates
  page/notebook conflict or Tombstone records; it does not imply general
  resource creation support.
- Preserve concurrent page/notebook content in durable conflict records. Keep
  the original unchanged, reserve a stable copy ID, derive display labels as
  `原名称（冲突副本）` or `第 N 页（冲突副本）`, and keep device/time as metadata.
  Keep Original and Use Conflict Version retain recovery history; Keep Both
  materializes the reserved ID with `conflictOf` ancestry. Repeated commit and
  resolution requests must not duplicate conflicts, resources, Revisions, or
  change events.
- Persist received conflict events in a separate account/device sidecar. A
  conflict-only change range is applied atomically before its Cursor advances;
  a mixed range remains at the prior Cursor until all included resource changes
  can be applied together. Conflict arrival uses a persistent header badge and
  user-opened list rather than interrupting the editor with a modal.
- Treat conflict resolution as endpoint confirmation followed by a normal
  Cursor pull, not as a local-only dismissal. Mixed resource/conflict ranges
  must apply the resource first, rebuild mappings, persist the resolved
  conflict, and only then advance the Cursor. Keep Both may append a reserved
  page copy only at the final server position; other structural additions stay
  reconciliation-safe.
- Store Flutter sync state under an account/device sidecar, not inside notebook
  JSON. Coalesce unsent edits per resource while preserving the oldest
  `baseRevision`; freeze an in-flight request until exact retry succeeds; keep
  newer local edits pending and rebase them from per-operation commit results.
  Advance the opaque pull Cursor only after the complete change page is safely
  applied locally, never merely because `/sync/commit` returned `nextCursor`.
- Keep asset cleanup operator-run and dry-run by default: expired pending
  uploads receive a 24-hour staging grace period, cancelled/completed residue
  waits 1 hour, final orphans are quarantined for 7 days, and every final object
  is rechecked against `assets.object_key` immediately before deletion.
- Treat `assets` rows as the ready/restorable boundary. Bootstrap exposes their
  stable IDs, notebook-relative paths, media metadata, byte size, and SHA-256
  only; it excludes upload sessions, object keys, and signed URLs. Clients
  obtain a fresh per-asset URL and must verify downloaded bytes before local
  application.
- Treat revision numbers and content hashes as server-owned. For the current
  backend slice, hash UTF-8 JSON with recursively sorted keys, compact
  separators, preserved Unicode/array order, and rejected non-finite numbers;
  freeze matching cross-client numeric serialization before Flutter computes
  or compares canonical hashes itself.
- Reconcile first-sign-in shared content through the server instead of
  calculating canonical hashes in Dart: submit `baseRevision: 0`, accept
  Content Hash equality as unchanged, preserve notebook/page divergence as a
  conflict, and stop on unsupported structural, attachment, or canvas
  divergence.
- Continue App integration against existing backend contracts before proposing
  new routes. `/sync/changes` download must be connected before expanding
  conflict presentation APIs, and its `nextCursor` is not persisted until the
  complete returned page has been applied locally.
- Treat additive cloud-only roots as the first safe incremental-application
  boundary. Existing-resource changes require local Revision/mapping metadata
  and a connected pending upload queue; until then they must remain unapplied
  with the prior Cursor preserved.
- Seed local-to-cloud resource mappings only after a verified bootstrap/merge
  application. A legacy initialized session with local notes but no mapping
  re-enters the safe first-sign-in Merge path instead of guessing remote page
  IDs. Page saves remain locally successful if queue-sidecar persistence fails.
- Treat `/sync/commit` as a content plus explicit notebook-metadata contract.
  Notebook title, archive state, and an already-synchronized folder ID travel
  in `metadata/baseMetadata`, never inside content. Folder create/rename/delete
  uses its own revisioned operation; deleting a folder moves its notebooks to
  the root and never creates a Tombstone. A paged notebook's complete mapped
  `pageOrder` and its applied baseline travel in the same metadata contract.
  Infinite-canvas `background` and its applied baseline use the canvas
  metadata contract; both remain outside JSON content.
  Submit notebook/canvas content only when every page/asset reference can be
  rewritten to verified cloud state; persist the local operation before that
  preflight so a later Retry cannot lose the user's sync intent.
- Before an initialized device submits content that references a new local
  attachment, upload it through the existing retryable session, verify its
  bootstrap metadata, byte size, and SHA-256, persist the cloud asset key, and
  only then submit the frozen content batch. Upload failure keeps the content
  operation queued for the existing non-blocking Retry flow.
- Allow deletion of any mapped page while at least one page remains. The server
  stores the original notebook/position in the Tombstone, compacts active page
  positions transactionally, and restores the page at that position while
  shifting later pages. Standalone canvas deletion has no App action; deleting
  an infinite-canvas notebook uses notebook deletion.
- Apply shared pull content from the final typed bootstrap snapshot, but require
  every `/sync/changes` Revision between the mapped local baseline and that
  snapshot. Reject gaps, structural divergence, unknown attachments, conflicts,
  and unsupported page/canvas Tombstones without advancing Cursor. A whole-
  notebook delete is applied only with its matching active Tombstone and an
  unchanged mapped baseline, after preserving the local directory for recovery.
  Suppress mutation tracking during remote application so downloaded content is
  not re-enqueued as upload.
- Use email/password for the first account flow without mandatory email
  verification during initial development. Use short-lived JWT access tokens
  and rotating opaque refresh tokens; store only refresh-token hashes and bind
  sessions to server-revocable devices.
- Keep the development login limiter process-local while the API uses a single
  process; require shared limiter storage before a multi-instance production
  topology so limits cannot be bypassed across instances.
- Keep non-secret defaults in Pydantic, host overrides in `server/.env`,
  optional container API overrides in ignored `server/.env.compose`, and only
  container topology or explicit service credential mappings in Compose
  `environment`; do not mirror every new application setting into Compose.
- Use `docs/development/POST_MVP_ROADMAP.md` for GoodNotes / Notability-style post-MVP planning.
- Prefer collapsing on-canvas zoom chrome and keeping Fit Width / Fit Page discoverable from More → View so the paper stays primary while writing.
- Prefer anchored tool-property popovers on regular/wide iPad widths; keep bottom sheets only for compact Split View.
- Keep notebook location and ink history in the document bar; show Record at
  ≥720px and Export at ≥1000px; use the header pager for adjacent page work,
  give Pages, Outline, and Bookmarks separate focused panels, and group
  remaining overflow actions by Document, Audio, and View; keep direct tools,
  contextual style, and touch mode in the editing dock; keep presets inside
  properties instead of persistent chrome.
- Treat Finger writes as the quiet default and Finger moves as the strongly selected touch mode.
- Use `docs/development/SUBSCRIPTION_PLAN.md` as the product reference for Free, InkNest Cloud, and future Pro monetization.
- Long-term product direction: iPad handwriting/PDF study, phone capture/review, and Web Yuque-like knowledge base.
- Use a custom two-finger zoom/pan viewport instead of `InteractiveViewer` so single-pointer drawing remains reliable.
- Keep every page layer at the persisted document size and apply one shared D→R→V transform for page rotation, zoom, pan, rendering, and hit testing.
- Start each page in Fit Width; expose Fit Page explicitly, enter Custom on the first content/pan/zoom gesture, and remember mode, scale, and focus per page for the editor session.
- Keep finger drawing available by default; use an explicit Finger pan mode to make touch drag the page while stylus/mouse input writes.
- Apply Finger Writing Assist only after a touch stroke completes; preserve its endpoints, pressure samples, and timestamps so persistence, audio replay, export, and recognition continue to share the same stroke model.
- Keep Finger Writing Assist enabled by default with an editor toolbar toggle, and never apply it to Apple Pencil/stylus or mouse strokes.
- Use corner-aware smoothing for Finger Writing Assist so small sampling jitter is reduced without rounding intentional handwriting corners aggressively.
- Keep page thumbnails lightweight, but show them through a collapsible wide Pages navigator or an on-demand Pages panel instead of a permanent bottom strip; Outline and Bookmarks use separate focused panels.
- Store a backward-compatible template enum on `NotePage`; older or unknown JSON values fall back to blank.
- Support Blank, Ruled, Dotted, Grid, Cornell, and Planner templates through one shared geometry layout used by the editor, page thumbnails, and PDF export.
- Let added and inserted non-PDF pages inherit the nearest prior template, preserve templates when duplicating pages, and keep PDF background pages template-free.
- Store page operations in the repository layer: duplicate inserts after the source page, delete keeps at least one page, and reorder starts with thumbnail menu move-left/move-right actions.
- Store page orientation as a backward-compatible `rotationQuarterTurns` value while preserving the original page size and all content coordinates, avoiding cumulative geometry drift across repeated rotations.
- Rotate the complete page surface as one layout unit so PDF backgrounds, templates, strokes, images, text, shapes, Smart Ink selection, search highlights, and pointer hit testing share the same transform.
- Let new and inserted blank pages inherit the nearby page orientation, preserve orientation when duplicating pages, and rotate exported PDF page dimensions and content together.
- Use a dedicated Lasso editor tool for freeform stroke selection, including strokes enclosed by the polygon or crossing its boundary.
- Keep selected stroke IDs in editor state; preview move and resize changes in memory, then persist the transformed strokes when the gesture completes.
- Preserve stroke IDs, pressure samples, timestamps, and audio links during lasso transforms; proportional resizing scales both points and stroke widths.
- Keep the lasso action toolbar above the rotated page surface so recolor, delete, and clear controls remain upright; selecting Lasso temporarily disables Finger pan to avoid competing one-finger gestures.
- Expose multi-PDF import from the open notebook editor and append imported pages in picker order, then navigate to the first newly imported page.
- Inspect PDF page counts and outlines through a small injectable `PdfImportInspector`; production uses `pdfrx`, while repository tests use deterministic metadata without native PDFium.
- Store PDFs added to an existing notebook under unique notebook-relative `assets/pdfs/` paths so same-named files do not overwrite one another; retain `assets/imported.pdf` compatibility for notebooks created from the library import flow.
- Add one top-level outline entry per appended PDF, preserve its nested source outlines, and keep existing notebook pages, outlines, bookmarks, and audio metadata intact.
- Inspect accurate rotated PDF page width and height through `pdfrx` alongside page count and outlines; store those dimensions on each imported `NotePage` for both library import and editor multi-PDF append.
- Fall back to the existing 768x1024 notebook page only when a source page size is missing, non-finite, or non-positive; existing notebooks keep their persisted dimensions unchanged.
- Use shared stroke geometry helpers for smoothed screen drawing, thumbnail drawing, PDF export paths, and partial eraser stroke splitting.
- Keep archived notebooks out of the default library list; show them through an explicit archived view where they can be restored or deleted.
- Store folders as first-class repository metadata; keep folders one level deep for now, and use `Notebook.folderId` to move notebooks between the root library and a folder.
- Keep library search and sort as UI-level derived state over repository results for now.
- Do not load first-page notebook thumbnails on the spine-based home shelf; identify books through stable spine color, title, page count, and state icons while retaining editor page thumbnails.
- Keep Recent as a library sort mode, but do not duplicate recently updated notebooks in a separate home-screen strip.
- Use one integrated library header and visible command bar above a lazy responsive shelf of gapless outward-facing spines; derive bounded spine width from page count, give every spine the same 3-degree leftward bottom-pivot lean, and retain whole-spine open targets plus accessible overflow actions.
- Reload repository-derived library metadata whenever the editor route closes so page count, page-derived width, recent sorting, and the next editor session never reuse a stale notebook snapshot.
- Keep normal notebook opening as one tap: animate forward at 1.04x for 200ms, retain the 3-degree left lean, then open; long press, pointer hover, or keyboard focus may hold inspection without requiring two taps.
- Measure rendered spine titles before creating a title tip, keep complete titles tip-free, and skip the wait and spatial motion when platform animation is disabled.
- Store blank-page insertion in the repository layer; inserted pages inherit the nearest page size but start without PDF background or strokes.
- Store imported PDF outlines on `Notebook.pdfOutlines`, keyed to notebook page IDs so page insertion and reordering do not break outline navigation.
- Store user page bookmarks on `Notebook.bookmarkedPageIds` and persist them through the repository layer.
- Let PDF import continue when outline loading fails; the Outline panel simply starts empty.
- Track Smart Ink in the existing post-MVP roadmap rather than a separate plan for now: rough finger handwriting -> recognition -> user confirmation -> neat handwriting-style editable text.
- Use `docs/development/SMART_INK_PLAN.md` as the dedicated Smart Ink planning document while keeping implementation after the current PDF workflow and Rich Notes prerequisites.
- Export PDF opens a scope dialog before the save flow and can export the full notebook, current page, or an ordered page/range expression.
- PDF export caches rendered PDF backgrounds during a single export and reuses opened PDF documents per file path.
- Default to Balanced export at 2x/up to 2400px with JPEG quality 88; Compact uses 1.25x/up to 1600px with JPEG quality 72, while Best uses 3x/up to 3600px with lossless PNG.
- Apply export quality settings only to flattened PDF background rasters; keep handwriting strokes and shapes as vector paths so Compact does not blur ink.
- Use one Pages field for PDF export expressions such as `1,3,5-7`; preserve the user's first-listed order, remove duplicate pages, and reject malformed, descending, or out-of-bounds ranges before opening the save dialog.
- Keep existing current-page and contiguous-range filename suffixes; use `-selected-pages` for non-contiguous exports to avoid excessively long filenames.
- Editor PDF background views reuse document references by file path and isolate background repainting with `RepaintBoundary`.
- Store typed note content on `NotePage.textBoxes` as `NoteTextBox` objects with page coordinates, color, width, and font size.
- Text boxes first support add, edit, move, delete, persistence, page duplication, thumbnails, and PDF export.
- Store text rendering style on `NoteTextBox.style`; support regular and handwriting-style text boxes.
- Text-box PDF export rasterizes Flutter-rendered text into PNGs before embedding them, preserving Unicode/CJK text and handwriting-style rendering without relying on `pdf` package default fonts.
- Smart Ink uses the existing Lasso selection context: select rough strokes, invoke Smart Ink from the upright selection toolbar, confirm recognized text, then insert a handwriting-style text box and optionally replace the ink.
- Automatic handwriting recognition is still future work; the current Smart Ink flow establishes the explicit selection and confirmation UX without sending handwriting off-device.
- Store inserted images on `NotePage.images`; file-backed notebooks copy image files into notebook-relative `assets/images/` paths and resolve them at load time.
- Render images below handwriting strokes, with move/delete/resize controls above the drawing canvas so users can write over inserted images.
- PDF export embeds inserted page images as PNG-backed PDF image widgets before vector handwriting strokes and text boxes.
- File-backed JSON writes use temporary-file replacement, and page saves are serialized to avoid transient empty JSON reads during high-frequency edits such as image dragging.
- Store clean shape objects on `NotePage.shapes`; first shape tool supports line, arrow, rectangle, and ellipse with light line-angle snapping for cleaner line/arrow creation.
- Shape rendering is shared across the editor, page thumbnails, and PDF export.
- Keep four complete pen/highlighter presets in the responsive tool dock; compact widths use a labelled Presets menu and no control floats over the paper.
- Use the `record` Flutter package for first-pass cross-platform microphone capture.
- Store audio recordings as notebook-level attachments under notebook-relative `assets/audio/` paths; keep the starting page on the recording and timeline linkage on `Stroke.audioRecordingId`.
- iOS declares `NSMicrophoneUsageDescription`; Android declares `RECORD_AUDIO` and keeps `minSdk` at least 23 for the recorder plugin.
- Use `just_audio` for local recording playback on the primary iOS/iPadOS and Android targets, and create the player lazily when playback first starts.
- Tag strokes completed during recording with `audioRecordingId`; playback keeps all ink visible and uses existing stroke-point timestamps to spotlight the current segment.
- Follow linked pages during audio playback by default; a manual page change pauses following until the user enables it again from the playback bar.
- Page saves merge the latest notebook index metadata before updating `updatedAt`, preventing delayed drawing saves from removing newly added audio recordings.
- Extract embedded PDF text with `pdfrx`, cache it by file path and source page number, and reuse the index for duplicated notebook pages and later searches.
- Map PDF search character bounds through the same contain-and-center layout as the page background; selecting a result jumps to the notebook page and highlights the match.
- Keep PDF highlight bounds in document coordinates so the shared viewport transform preserves alignment through resize, zoom, and page rotation.
- Search scanned PDF pages through the shared ML Kit Text Recognition raster
  pipeline when no usable embedded text layer is available.
- Use one editor search entry point for embedded PDF text and `NotePage.textBoxes`; confirmed Smart Ink content is searchable because it is stored as handwriting-style editable text.
- Keep raw handwriting strokes out of automatic notebook search until the user
  confirms a Digital Ink candidate; confirmed Smart Ink remains searchable as
  editable text, while scanned PDF pages and inserted images are indexed by
  ML Kit Text Recognition.
- Keep PDF coordinate highlights for embedded-text results and highlight the matched editable text box after cross-page navigation.
- Keep raster PDF/image OCR and vector handwriting recognition behind separate
  Flutter contracts: ML Kit Text Recognition receives bounded RGBA images,
  while ML Kit Digital Ink receives original stroke coordinates and timestamps.
- Lazily download a real-device-locale-priority `zh-Hani-CN`, `zh-Hani-TW`,
  `zh-Hani-HK`, or `en-US` Digital Ink model, fall back to the other language
  when no candidate is returned, and keep manual Smart Ink confirmation as the
  safe recovery path.
- Use ML Kit Digital Ink for vector handwriting recognition on both iOS and
  Android; do not keep an Apple Vision or PencilKit recognition branch.
- Keep native minimum-version requirements aligned with the selected ML Kit
  Flutter plugins; Digital Ink currently requires iOS 15.5 or newer.
- Persist `NotePage.coordinateSpaceVersion`: new pages use canonical v1, missing values read as legacy v0, empty v0 pages upgrade losslessly, and non-empty legacy or unsupported pages remain repository-enforced read-only.
- Keep unresolved legacy content viewable, navigable, zoomable, searchable, and exportable without allowing normal save, rotate, copy, or duplicate paths to overwrite its source JSON.

## Verification

- Fixed-layout Smart Ink tests cover all bundled fonts, long single-line text,
  explicit multi-line text, painted stroke bounds, and recomputed lasso bounds.
  The complete 281-test Flutter suite and `flutter analyze` pass.

- The supplied physical-device log proves both `zh-Hani-CN` and `en-US` models
  were downloaded and native recognition returned before the plugin crashed on
  an integer score. A new channel regression test now covers integer `0` scores;
  all 279 Flutter tests and `flutter analyze` pass.

- Focused Digital Ink and editor widget tests pass with the new diagnostic
  events, and `flutter analyze` reports no issues. Test logs verify both the
  model-unavailable and successful-candidate paths without printing candidate
  text.

- Smart Ink model/geometry regression coverage, the complete 278-test Flutter
  suite, and `flutter analyze` pass. An iOS simulator debug build succeeds with
  the supported Chinese model identifiers and device-locale selection. ML Kit
  still requires physical-device accuracy and initial model-download checks.

- The unified ML Kit recognition implementation passes all 277 Flutter tests,
  `flutter analyze`, and `git diff --check`. Debug native builds succeed for the
  iOS simulator and Android APK. Focused coverage verifies Digital Ink stroke
  conversion, model/language fallback, inserted-image OCR caching and coordinate
  highlights, scanned-PDF OCR fallback, and unified PDF/image/typed/Smart Ink
  search results. Physical-device accuracy and first-model-download behavior
  remain to be validated.

- The repository contains the official AGPLv3 and CC BY-SA 4.0 texts, explicit
  scope/commercial/trademark/contribution policies, retained OFL notices, and
  `AGPL-3.0-only` Python package metadata. Resolved Flutter and direct Python
  dependency licenses were inventoried with no obvious blocking
  incompatibility. The server sdist/wheel build succeeds, includes the complete
  AGPL text, and all new local Markdown links plus `git diff --check` pass.

- The focused infinite-canvas widget test, all 270 Flutter tests, and
  `flutter analyze` pass after adding the viewport output clip.

- Focused first-sign-in dialog and Merge-service tests pass, including a failed
  mixed Merge followed by a successful Retry. `flutter analyze` reports no
  issues, and `git diff --check` passes.

- Focused editor coverage passes at 320×568 and 390×844 for infinite canvas and
  at 390×844 for paged notes. Both compact headers keep their document context
  separate from navigation/tools without a RenderFlex exception; regular iPad
  layouts remain unchanged, actions keep their target size, and extremely
  narrow canvas tools scroll instead of shrinking. The complete Flutter suite
  passes all 265 tests, `flutter analyze` reports no issues, and
  `git diff --check` passes.

- `bash -n scripts/stop_dev_app.sh` and root `make -n restart` pass. Root
  `make restart` only clears stale Flutter/iOS debug helpers then relaunches
  the App. Not executed live because a host API was already running in the
  user's terminal.

- Flutter's full 264-test suite and `flutter analyze` pass after the Phase 5
  implementation audit. Focused coverage proves that a new initialized-device
  attachment is retried, bootstrap-verified, and marked cloud-ready before its
  queued content commit; a failed first upload preserves the operation and
  asset state. Canvas-notebook shelf deletion is also verified to queue a
  Notebook delete and preserve `canvas.json` in the recovery copy. No backend
  route, database model, or Alembic migration changed; `git diff --check`
  passes.

- Python formatting, Ruff, and mypy pass. All 65 non-integration tests and 16
  PostgreSQL/MinIO integration tests pass, including a real PostgreSQL startup-
  guard check. The development database and repository both report
  `20260807_0014 (head)`, `alembic check` reports no pending operations, Compose
  configuration is valid, and `git diff --check` passes. No migration or table
  change was required for this operational safety slice.

- Flutter formatting, the full 230-test suite, `flutter analyze`, and
  `git diff --check` pass after conflict resolution integration. Focused tests
  cover the authenticated endpoint contract, response/change aliases,
  persisted resolution, stale-original mapping, mixed resource/conflict
  ranges, Keep Both page append, replacement confirmations, completion
  feedback, and badge removal. No backend or schema files changed.

- Flutter's full 183-test suite passes and `flutter analyze` reports no issues.
  New restore tests cover a complete cloud-only restore, size/SHA failure with
  zero local mutation, apply-time rollback, Cursor gating, and signed object
  download without leaking the API Authorization header.
- Python formatting, Ruff linting, and mypy pass. All 49 non-integration and 15
  PostgreSQL/MinIO integration tests pass, including path traversal/kind
  rejection and ready-asset bootstrap transfer.
- Alembic upgraded both the development database and an independent empty
  verification database to `20260806_0012 (head)`; `alembic check` reports no
  pending schema operations.

- Flutter formatting, all 178 tests, and `flutter analyze` pass after the Dio,
  secure-session, automatic-refresh, and Account UI integration. Focused tests
  cover session round-trip, one shared concurrent refresh, one-time 401 retry,
  rejected-refresh invalidation, form validation/errors, compact large-text
  accessibility, and sign-out preserving a local notebook. No backend schema or
  Alembic migration changed in this slice.

- Python formatting, Ruff checks, and mypy pass across 66 source files. All 48
  non-integration tests and all 15 PostgreSQL/MinIO integration tests pass,
  including atomic library creation, ready-only asset bootstrap scoping, hidden
  MinIO keys/URLs, and real PDF/image/audio upload → verification → inventory →
  download byte round trips. OpenAPI still exposes 19 operations. No Alembic
  migration was created because this slice reuses existing asset and library
  tables.

- The 9 focused Flutter bootstrap/Merge tests pass, covering four presence
  states, local inventory discovery, response validation, stable-ID-only action
  selection, deterministic retry ordering, empty plans, and corrupt-ID
  rejection. The full Flutter suite passes all 162 tests and `flutter analyze`
  reports no issues. No Python, PostgreSQL, MinIO, API, dependency, or schema
  code changed, so backend tests and Alembic were not rerun for this slice.

- Flutter bootstrap's 5 focused tests and the full 158-test suite pass;
  `flutter analyze` reports no issues. Python formatting, linting, and strict
  typing pass; all 43 non-integration tests and all 14 PostgreSQL/MinIO
  integration tests pass. OpenAPI exposes 18 application operations, including
  the authenticated read-only bootstrap inventory. No Alembic migration was
  created because this slice changes no database schema.

- `dart format` and the 11 focused Flutter sync-state tests pass. The full
  Flutter suite passes all 153 tests, and `flutter analyze` reports no issues.
- Backend formatting, linting, and strict typing pass; all 41 non-integration
  tests pass, including atomic rollback of a failed multi-operation batch.
- All 13 PostgreSQL/MinIO integration tests pass, including offline edits to
  different pages and exact replay after a successful commit response is lost.

- Backend formatting, linting, and strict typing pass; all 40 non-integration
  tests pass, including soft deletion, idempotent replay, restore, and both
  sequential delete-edit arrival orders.
- All 11 PostgreSQL/MinIO integration tests pass, including a real concurrent
  delete/edit race whose final resource always contains the edited content.
- Alembic upgraded the development database to `20260806_0011 (head)` with no
  schema drift. An independent empty PostgreSQL database upgraded from `0001`
  through `0011` and was deleted after verification.
- OpenAPI exposes 17 application operations, including explicit Tombstone
  restore and delete/Tombstone outcomes on the idempotent commit contract.

- Backend formatting, linting, and strict typing pass across 61 Python
  source/test files; all 37 non-integration tests pass.
- All ten PostgreSQL/MinIO integration tests pass, including concurrent retries
  of one stale sync commit producing exactly one conflict record and one
  conflict change event.
- Alembic upgraded the development database to `20260806_0010 (head)` with no
  schema drift. An independent empty database upgraded from `0001` through
  `0010`, exposing `conflicts` and page/notebook `conflict_of`, then was deleted.
- OpenAPI now exposes 16 application operations, including conflict resolution
  alongside structured `applied`, `unchanged`, and `conflict` commit outcomes.
- Flutter formatting, all 151 tests, and static analysis pass after adding the
  local sync state layer. Nine focused tests cover restart persistence,
  per-resource coalescing, exact in-flight retries, edit-during-upload
  rebasing, response validation, initial Cursor gating, account/device
  isolation, concurrent queue writes, and corrupt-state preservation.
- Backend formatting, linting, and strict typing pass across 60 Python
  source/test files; all 36 non-integration tests pass.
- All nine PostgreSQL/MinIO integration tests pass, including concurrent
  PostgreSQL replay of one idempotent sync commit with exactly one Revision and
  change event.
- Alembic upgraded the development database to `20260806_0009 (head)`. An
  independent empty database upgraded through `0009` and was deleted after
  verification.
- OpenAPI exposes 15 application operations, including authenticated pull via
  `GET /api/v1/sync/changes` and atomic push via `POST /api/v1/sync/commit`.
- Backend formatting, linting, and strict typing pass across 52 Python
  source/test files; all 30 non-integration tests pass.
- All seven PostgreSQL/MinIO integration tests pass, including real staging
  deletion, orphan candidate registration, quarantine, and final deletion.
- Alembic upgraded the development database to `20260806_0007 (head)` and
  reports no schema drift. The real local cleanup command returned a zero-count
  dry-run without modifying PostgreSQL or MinIO.
- An independent empty PostgreSQL database upgraded from the baseline through
  `20260806_0007`, exposed the expected 12 public tables including
  `asset_gc_candidates`, and was deleted after verification.
- Backend formatting, linting, and strict typing pass across 48 Python
  source/test files; all 28 non-integration tests pass.
- Six PostgreSQL/MinIO integration cases pass. PDF, PNG image, and M4A audio
  each travel through a real presigned PUT, completion verification and
  promotion, owner-scoped presigned GET, and byte-for-byte download check.
- OpenAPI exposes 13 application operations, including
  `GET /api/v1/assets/{asset_id}/download-url`; Alembic remains at the verified
  `20260806_0006` head because this slice changes no database schema.
- Backend formatting, linting, and strict typing pass across 48 Python
  source/test files; all 28 non-integration tests pass.
- All four PostgreSQL/MinIO integration tests pass. The asset test now uploads
  through a real presigned PUT URL, confirms the pending boundary, conditionally
  promotes and hashes the object, creates one ready asset, and verifies a
  repeated completion is idempotent.
- Alembic upgraded the development database to `20260806_0006 (head)` and
  reports no schema drift. An independent empty database upgraded from `0001`
  through `0006`, exposing 11 tables plus `staging_object_key` and
  `completed_at`, before the scratch database was deleted.
- Backend formatting, linting, and strict typing pass across 48 Python
  source/test files; all 26 non-integration tests pass.
- All four PostgreSQL/MinIO integration tests pass. The new test creates a real
  presigned URL, uploads bytes directly to private MinIO, confirms the upload
  remains `pending` with no ready `assets` row, and deletes the test object.
- Alembic upgraded the real development database to `20260805_0005 (head)`,
  `alembic check` reports no pending operations, and an independent empty
  scratch database upgraded from `0001` through `0005` with the expected 11
  public tables before being deleted.
- `docker compose config --quiet` passes with separate internal MinIO and
  client-visible signing endpoints.
- Backend formatting, linting, and typing pass with `ruff format --check`,
  `ruff check`, and `mypy` across 42 Python source/test files; all 23 unit tests
  pass.
- All three PostgreSQL/MinIO integration tests pass, including real revision
  history persistence and concurrent different-content writes from the same
  base: one creates Revision 1 and the other receives an explicit conflict.
- Alembic upgraded the real development database to `20260805_0004 (head)`,
  `alembic check` reports no pending operations, and PostgreSQL contains the
  `revisions` table plus current `content`, `revision`, and `content_hash`
  columns on notebooks, pages, and infinite canvases.
- An independent empty scratch database upgraded through migrations `0001` to
  `0004`; the expected ten tables and twelve revision-content columns were
  inspected before the scratch database was deleted.
- Backend formatting, linting, and typing pass with `ruff format --check`,
  `ruff check`, and `mypy` across 38 Python source/test files; all 19 unit tests
  pass.
- Both PostgreSQL/MinIO integration tests pass, including real PostgreSQL
  persistence of identical client IDs under two different users with isolated
  reads.
- Alembic upgraded the real development database to `20260805_0003 (head)`,
  `alembic check` reports no pending operations, and PostgreSQL contains the
  new `folders`, `notebooks`, `pages`, `infinite_canvases`, and `assets` tables.
- An independent empty scratch database upgraded through migrations `0001`,
  `0002`, and `0003`; all nine expected tables and the final version were
  inspected before the scratch database was deleted.
- Backend formatting, linting, and typing pass with `ruff format --check`,
  `ruff check`, and `mypy` across 34 checked Python source/test files.
- All 15 backend unit tests pass, including login-limit account/client,
  cross-account IP, expiry, cancellation, and successful-login reset coverage;
  the PostgreSQL/MinIO integration test also passes.
- Alembic upgraded the real local PostgreSQL database from `20260805_0001` to
  `20260805_0002 (head)`; `alembic check` reports no pending schema operations,
  and PostgreSQL contains `users`, `devices`, and `refresh_tokens` alongside
  `alembic_version`.
- Alembic also upgraded an independent empty scratch database through
  `20260805_0001` and `20260805_0002`; the expected four tables and migration
  head were verified, then the scratch database was deleted successfully.
- `docker compose config --quiet` passes, the user confirmed the complete stack
  starts successfully, and `/api/v1/health/ready` reports both PostgreSQL and
  MinIO available. The Alembic empty baseline is present in the real database.
- Compose also resolves successfully when the optional
  `server/.env.compose` file is absent; the API container's explicit
  environment is limited to database, MinIO, and JWT container mappings.
- Uvicorn reached application startup on the host runtime, but sandbox network
  isolation prevented an HTTP probe; the temporary validation process was
  stopped afterward.
- The project-local `inknest-backend` Skill passes the official
  `quick_validate.py` check; PyYAML was installed only under `/tmp` to run the
  validator and was not added to project dependencies.
- `git diff --check` and trailing-whitespace checks passed for the accepted
  Python/PostgreSQL/MinIO backend product brief, implementation plan, roadmap,
  decision log, and status updates; no application code changed.
- `flutter analyze` and all 142 tests pass after replacing the Infinite canvas
  spine metadata with a visible `∞` marker and full accessibility label;
  paged notebooks retain compact page counts.
- `flutter analyze` and all 141 tests pass after adding shared Lasso, text,
  image, and shape editing to Infinite canvas.
- Infinite-canvas interaction coverage includes text create/edit/move/delete,
  image insert/move/resize/delete, shape drawing, ink Lasso deletion,
  rich-content persistence, fit-content bounds, and content undo/redo.
- The shared single top bar passes at 600×800, 834×1194, and 1194×834 with
  Pen, Highlighter, Eraser, Lasso, and Insert available without overflow.
- `flutter analyze` and all 138 tests pass after merging the infinite-canvas
  editing tools into one responsive top bar.
- Infinite-canvas single-bar widget coverage passes at 600×800, 834×1194, and
  1194×834 without overflow or loss of core controls.
- `flutter test` passed with 133 tests after splitting Pages, Outline, and
  Bookmarks and adding paper-style-first page insertion.
- `flutter analyze` passed with no issues after Editor Workspace V2.
- Focused responsive and toolbar tests passed at 600×800, 834×1194, and
  1194×834, covering document/history hierarchy, direct Pen/Highlighter
  switching, selected-tool properties, contextual presets, adaptive
  Record/Export visibility, focused navigation panels, insertion cancellation
  and selected paper styles, persistent Pages management, and labelled More
  sections without duplicate page actions.
- `git diff --check` passed after Editor Workspace V2.
- `dart format` passed for the editor interaction polish changes on 2026-07-27.
- `flutter test` passed with 126 tests after editor interaction polish.
- `flutter analyze` passed with no issues after editor interaction polish.
- Focused toolbar, workspace, and viewport model tests cover collapsed zoom chrome, More → View fit actions, properties popover, and Finger mode hierarchy.
- `git diff --check` passed after the editor interaction polish.
- `dart format` passed for the editor workspace, viewport, model, repository,
  and test changes on 2026-07-27.
- `flutter test` passed with 122 tests after the editor workspace redesign,
  fixed-coordinate viewport, coordinate-version write gate, and dead-code
  cleanup.
- `flutter analyze` passed with no issues after the editor workspace redesign
  and dead-code cleanup.
- Focused responsive tests passed at 600×800, 834×1194, and 1194×834,
  including fixed 768×1024 document layout through viewport rotation.
- Legacy UI and repository tests confirm that non-empty v0/unsupported pages
  remain readable but cannot be overwritten by normal saves.
- `dart format lib test` passed.
- `flutter test` passed.
- `flutter analyze` passed.
- `git diff --check` passed after the post-MVP documentation update.
- `dart format lib test` passed after editor zoom/pan.
- `flutter test` passed after editor zoom/pan.
- `flutter analyze` passed after editor zoom/pan.
- `dart format lib test` passed after Finger pan mode.
- `flutter test` passed after Finger pan mode.
- `flutter analyze` passed after Finger pan mode.
- `dart format lib test` passed after page thumbnails.
- `flutter test` passed after page thumbnails.
- `flutter analyze` passed after page thumbnails.
- `dart format lib test` passed after page duplicate/delete/reorder.
- `flutter test` passed after page duplicate/delete/reorder.
- `flutter analyze` passed after page duplicate/delete/reorder.
- `dart format lib test` passed after stroke smoothing and partial erasing.
- `flutter test` passed after stroke smoothing and partial erasing.
- `flutter analyze` passed after stroke smoothing and partial erasing.
- `dart format lib test` passed after notebook library actions.
- `flutter test` passed after notebook library actions.
- `flutter analyze` passed after notebook library actions.
- `dart format lib test` passed after folders.
- `flutter test` passed after folders.
- `flutter analyze` passed after folders.
- `dart format lib test` passed after library search, sort, recent notebooks, and thumbnails.
- `flutter test` passed after library search, sort, recent notebooks, and thumbnails.
- `flutter analyze` passed after library search, sort, recent notebooks, and thumbnails.
- `git diff --check` passed after library search, sort, recent notebooks, and thumbnails.
- `dart format lib test` passed after inserting blank pages.
- `flutter test` passed after inserting blank pages.
- `flutter analyze` passed after inserting blank pages.
- `git diff --check` passed after inserting blank pages.
- `dart format lib test` passed after PDF thumbnails, outlines, and bookmarks.
- `flutter test` passed after PDF thumbnails, outlines, and bookmarks.
- `flutter analyze` passed after PDF thumbnails, outlines, and bookmarks.
- `git diff --check` passed after PDF thumbnails, outlines, and bookmarks.
- `git diff --check` passed after adding Smart Ink to the roadmap.
- `git diff --check` passed after adding `docs/development/SMART_INK_PLAN.md`.
- `dart format lib test` passed after page-range export.
- `flutter test` passed after page-range export.
- `flutter analyze` passed after page-range export.
- `git diff --check` passed after page-range export.
- `dart format lib test` passed after PDF background caching and export quality.
- `flutter test` passed after PDF background caching and export quality.
- `flutter analyze` passed after PDF background caching and export quality.
- `git diff --check` passed after PDF background caching and export quality.
- `dart format lib test` passed after text boxes.
- `flutter test` passed after text boxes.
- `flutter analyze` passed after text boxes.
- `git diff --check` passed after text boxes.
- `dart format lib test` passed after handwriting-style text rendering.
- `flutter test` passed after handwriting-style text rendering.
- `flutter analyze` passed after handwriting-style text rendering.
- `git diff --check` passed after handwriting-style text rendering.
- `dart format lib test` passed after Smart Ink beautify.
- `flutter test` passed after Smart Ink beautify.
- `flutter analyze` passed after Smart Ink beautify.
- `git diff --check` passed after Smart Ink beautify.
- `dart format lib test` passed after image insertion.
- `flutter test` passed after image insertion.
- `flutter analyze` passed after image insertion.
- `git diff --check` passed after image insertion.
- `dart format lib test` passed after serializing file-backed page saves.
- `flutter test` passed after serializing file-backed page saves.
- `flutter analyze` passed after serializing file-backed page saves.
- `git diff --check` passed after serializing file-backed page saves.
- `dart format lib test` passed after shape tool.
- `flutter test` passed after shape tool.
- `flutter analyze` passed after shape tool.
- `git diff --check` passed after shape tool.
- `dart format lib test` passed after favorites toolbar.
- `flutter test` passed after favorites toolbar.
- `flutter analyze` passed after favorites toolbar.
- `dart format lib test` passed after audio recording.
- `flutter test` passed after audio recording.
- `flutter analyze` passed after audio recording.
- `git diff --check` passed after audio recording.
- `dart format lib test` passed after audio timeline playback.
- `flutter test` passed with 40 tests after audio timeline playback.
- `flutter analyze` passed after audio timeline playback.
- `git diff --check` passed after audio timeline playback.
- `dart format lib test` passed after audio playback spotlight polish.
- `flutter test` passed with 41 tests after audio playback spotlight polish.
- `flutter analyze` passed after audio playback spotlight polish.
- `git diff --check` passed after audio playback spotlight polish.
- `dart format lib test` passed after PDF text search.
- `flutter test` passed with 45 tests after PDF text search.
- `flutter analyze` passed after PDF text search.
- `git diff --check` passed after PDF text search.
- `dart format` passed after fixing PDF search highlight alignment.
- `flutter test` passed with 47 tests after fixing PDF search highlight alignment.
- `flutter analyze` passed after fixing PDF search highlight alignment.
- `git diff --check` passed after fixing PDF search highlight alignment.
- `dart format lib test` passed after the handwriting recognition and OCR spike.
- `flutter test` passed with 51 tests after the handwriting recognition and OCR spike.
- `flutter analyze` passed after the handwriting recognition and OCR spike.
- `flutter build ios --simulator --no-codesign` passed with zero Xcode warnings after adding the Apple Vision bridge.
- `git diff --check` passed after the handwriting recognition and OCR spike.
- `dart format lib test` passed after unified notebook search.
- `flutter test` passed with 54 tests after unified notebook search.
- `flutter analyze` passed after unified notebook search.
- `git diff --check` passed after unified notebook search.
- `dart format lib test` passed after Finger Writing Assist.
- `flutter test` passed with 57 tests after Finger Writing Assist.
- `flutter analyze` passed after Finger Writing Assist.
- `git diff --check` passed after Finger Writing Assist.
- `dart format lib test` passed after page templates.
- `flutter test` passed with 62 tests after page templates.
- `flutter analyze` passed after page templates.
- `git diff --check` passed after page templates.
- `dart format lib test` passed after page rotation.
- `flutter test` passed with 66 tests after page rotation.
- `flutter analyze` passed after page rotation.
- `git diff --check` passed after page rotation.
- `dart format lib test` passed after lasso selection.
- `flutter test` passed with 70 tests after lasso selection.
- `flutter analyze` passed after lasso selection.
- `git diff --check` passed after lasso selection.
- `dart format lib test` passed after multi-PDF import.
- `flutter test` passed with 72 tests after multi-PDF import.
- `flutter analyze` passed after multi-PDF import.
- `git diff --check` passed after multi-PDF import.
- `dart format lib test` passed after non-contiguous selected-page export.
- `flutter test` passed with 79 tests after non-contiguous selected-page export.
- `flutter analyze` passed after non-contiguous selected-page export.
- `git diff --check` passed after non-contiguous selected-page export.
- `dart format lib test` passed after flattened PDF quality presets.
- `flutter test` passed with 81 tests after flattened PDF quality presets.
- `flutter analyze` passed after flattened PDF quality presets.
- `git diff --check` passed after flattened PDF quality presets.
- `dart format lib test` passed after preserving imported PDF page dimensions.
- `flutter test` passed with 81 tests after preserving imported PDF page dimensions.
- `flutter analyze` passed after preserving imported PDF page dimensions.
- `git diff --check` passed after preserving imported PDF page dimensions.
- Skill Creator `quick_validate.py` passed for `$inknest-product-manager`, `$inknest-ui-ux`, and the updated `$inknest-project`.
- Read-only forward testing confirmed that an underspecified WebDAV request stops at product/UI scope decisions instead of modifying code.
- `git diff --check` passed after adding the product and UI/UX workflow skills.
- `git diff --check` passed after favorites toolbar.
- `git diff --check` passed after adding graduation task book and opening report drafts.
- `git diff --check` passed after retitling graduation docs for Flutter and Python.
- `git diff --check` passed after improving graduation task book and opening report quality.
- `git diff --check` passed after reorganizing docs into development, academic, and learning directories.
- `git diff --check` passed after extracting academic writing requirements.
- `git diff --check` passed after optimizing the graduation task book and opening report for supervisor review.
- `git diff --check` passed after syncing academic progress plans to the 2026 summer adult-education graduation schedule.
- `git diff --check` passed after rechecking the task book against the downloaded task-book writing notes PDF.
- `git diff --check` passed after rechecking the opening report against the downloaded opening-report writing notes PDF.
- `git diff --check` passed after formalizing Python module wording in the graduation task book and opening report.
- `git diff --check` passed after removing submit-inappropriate maintenance wording from the graduation task book and opening report.
- `git diff --check` passed after replacing graduation document references with journal-title sources verified through the school library journal navigation page.
- `dart format lib test` passed after the responsive library bookshelf redesign.
- `flutter test` passed with 82 tests after the responsive library bookshelf redesign.
- `flutter analyze` passed after the responsive library bookshelf redesign.
- `git diff --check` passed after the responsive library bookshelf redesign.
- `dart format lib test` passed after unifying the library header and spine shelf.
- `flutter test` passed with 82 tests after unifying the library header and spine shelf.
- `flutter analyze` passed after unifying the library header and spine shelf.
- `git diff --check` passed after unifying the library header and spine shelf.
- `dart format lib test` passed after adding gapless, leaning, page-weighted spines.
- `flutter test` passed with 83 tests after adding gapless, leaning, page-weighted spines.
- `flutter analyze` passed after adding gapless, leaning, page-weighted spines.
- `git diff --check` passed after adding gapless, leaning, page-weighted spines.
- `dart format lib test` passed after making every shelf spine lean right from its bottom contact point.
- The focused adjacent-spine widget test passed after checking every rendered notebook leans in the same rightward direction.
- `flutter test` passed with 83 tests after the rightward-lean refinement and home-code cleanup.
- `flutter analyze` passed after the rightward-lean refinement and home-code cleanup.
- Static scans found no old Recent/grid/cover/search-toggle symbols, library thumbnail references, `Card`, or `CardTheme` usage in active code and tests.
- `git diff --check` passed after the rightward-lean refinement and home-code cleanup.
- `dart format lib test` passed after the fixed 3-degree spine lean and editor-return refresh.
- Focused widget tests passed for equal spine angles and the add-pages -> return -> reopen metadata flow.
- `flutter test` passed with 84 tests after the fixed 3-degree spine lean and editor-return refresh.
- `flutter analyze` passed after the fixed 3-degree spine lean and editor-return refresh.
- `git diff --check` passed after the fixed 3-degree spine lean and editor-return refresh.
- `dart format lib test` passed after switching the shared spine lean to 3 degrees leftward.
- The focused adjacent-spine widget test passed after verifying equal leftward rotation for every rendered notebook.
- `flutter test` passed with 84 tests after switching the shared spine lean to 3 degrees leftward.
- `flutter analyze` passed after switching the shared spine lean to 3 degrees leftward.
- `git diff --check` passed after switching the shared spine lean to 3 degrees leftward.
- `dart format lib test` passed after the notebook pull-forward interaction.
- Focused widget tests passed for opening delay, unchanged lean, long-press/hover inspection, outside retraction, conditional title tips, and reduced motion.
- `flutter test` passed with 87 tests after the notebook pull-forward interaction.
- `flutter analyze` passed after the notebook pull-forward interaction.
- `git diff --check` passed after the notebook pull-forward interaction.
- `git diff --check` passed after re-screening graduation document references against school library journal coverage years.
- `git diff --check` passed after splitting academic document maintenance into `$inknest-academic-docs`.
- `git diff --check` passed after replacing graduation references with 2022-2025 journal papers and adding one-to-one body citations.
- Read-only editor review confirmed that the current fitted page surface mixes
  screen-local input with persisted document coordinates and can misalign
  content after resize or rotation.
- Product and UI/UX proposals for the editor workspace and stable page viewport
  were completed; application implementation and migration are not started.
- `git diff --check` passed after the editor workspace product/UI proposal.
- Focused first-sign-in sync Widget tests passed for cloud-only confirmation,
  mixed-library non-mutation, and offline retry/continue behavior.
- `flutter test` passed with 186 tests after wiring visible bootstrap detection
  and pure cloud-only restore.
- `flutter analyze` passed after the first-sign-in sync flow.
- `git diff --check` passed after the first-sign-in sync flow.
- Flutter local-only upload tests passed for structure/page serialization,
  attachment hashing and transfer, final bootstrap verification, Cursor save,
  confirmation UI, and real API request paths.
- `flutter test` passed with 189 tests after local-only cloud protection.
- `flutter analyze` passed after local-only cloud protection.
- Backend Ruff formatting/lint, mypy, 49 non-integration tests, and 15 real
  PostgreSQL/MinIO integration tests passed after versioning notebook content
  during first Merge creation.
- `git diff --check` passed after local-only cloud protection.
- Fixed first local-only upload validation when multiple notebooks use the
  legacy notebook-scoped page ID `page-1`: upload now derives a stable remote
  page ID from notebook ID plus local page ID and rewrites transmitted bookmark,
  PDF outline, and audio page references without mutating local files.
- Focused Flutter tests passed for the typed `/sync/commit` request, shared
  unchanged/conflict result parsing, mixed upload/download orchestration,
  final Cursor persistence, incompatible shared-metadata blocking, and the
  enabled mixed Merge confirmation UI.
- `flutter test` passed with 192 tests after the mixed-library Merge slice;
  `flutter analyze` and `git diff --check` passed.
- Backend `uv run pytest tests/unit/test_sync_changes.py` passed with 11 tests,
  confirming unchanged-by-Content-Hash and Revision-conflict preservation used
  by the Flutter shared-content integration.
- Focused Flutter API/service tests pass after adding typed `/sync/changes`
  pagination and response parsing; the complete Flutter suite passes with 195
  tests, `flutter analyze` passes, and no backend source or route changed.
- Focused incremental-pull tests cover multi-page download, atomic cloud-only
  notebook application, final Cursor persistence, and shared-update blocking.
- Focused incremental-push tests cover page-save coalescing, persisted
  local/remote resource mappings, returned Revision updates, startup push-before-
  pull ordering, visible upload counts, and exact in-flight replay after a lost
  response.
- `flutter test` passes with 200 tests after the paged-note incremental upload
  slice; `flutter analyze` and `git diff --check` pass, and no backend source or
  route changed.
- Focused tests pass for notebook bookmark page-ID rewriting, exclusion of
  structural notebook fields, infinite-canvas content queueing, persisted cloud
  asset knowledge, and durable deferral of a canvas operation that references
  an unuploaded image.
- `flutter test` passes with 203 tests after notebook/canvas content tracking;
  `flutter analyze` and `git diff --check` pass, with no backend source or route
  change.
- `flutter test` passes with 206 tests after shared-content download application;
  focused coverage includes notebook page-reference reversal, page text content,
  infinite-canvas state, Cursor gating, and the visible “更新已有内容” result.
  `flutter analyze` and `git diff --check` pass; no backend route changed.
- `flutter test` passes with 214 tests after local whole-notebook delete upload;
  focused coverage includes queue coalescing, content-free commit serialization,
  response-loss retry, repository rollback, and same-device Tombstone
  confirmation. `flutter analyze` passes; no backend route changed.
- `flutter test` passes with 221 tests after safe trailing-page deletion upload
  and application; focused coverage includes queue rollback, middle-page gating,
  same-device confirmation, remote recovery files, and visible sync feedback.
  `flutter analyze` passes; no backend route changed.
- `flutter test` passes with 234 tests after active Tombstone persistence and
  Recently Deleted restore; focused coverage includes typed transport, durable
  active/restored state, local notebook reapplication, and the visible restore
  action. `flutter analyze` and `git diff --check` pass; no backend source or
  route changed in this App-integration slice.
- `flutter test` passes with 238 tests after visible sync status and retry;
  focused coverage includes in-progress/completed UI, durable failed-operation
  counts, retrying the frozen batch, and separate delete/edit-preserved
  feedback. `flutter analyze` and `git diff --check` pass; no backend source or
  route changed.
- `flutter test` passes with 241 tests after the new-device bootstrap handoff;
  focused coverage proves Cursor deferral, mapping-before-Cursor publication,
  direct incremental pull after simulated restart, and no early Cursor on
  mapping failure. `flutter analyze` and `git diff --check` pass; no backend
  source or route changed.
- `flutter test` passes with 245 tests after the verified recovery boundary;
  focused coverage proves snapshot cleanup on success and exact notebook,
  sidecar, resource-map obstacle, and Cursor restoration when cloud-only,
  mixed-Merge, or additive-download handoff fails. `flutter analyze` and
  `git diff --check` pass; no backend route changed.
- `flutter test` passes with 248 tests after notebook metadata synchronization;
  the backend passes 50 unit/API tests and 15 PostgreSQL/MinIO integration
  tests. Focused coverage includes durable metadata coalescing, cross-device
  title/archive/folder application, idempotent replay, and atomic same-field
  conflict rejection. Ruff, mypy, Flutter analysis, and diff checks pass.
- `flutter test` passes with 254 tests after folder creation/rename
  synchronization; the backend passes 51 unit/API tests and 15 PostgreSQL/
  MinIO integration tests. Alembic upgrades both the development database and
  an independent empty database to `20260807_0013`, with no schema drift.
- `flutter test` passes with 257 tests after safe folder deletion
  synchronization; the backend passes 52 unit/API tests and 15 PostgreSQL/
  MinIO integration tests. Focused coverage proves unsent-create cancellation,
  mapped delete queuing, cross-device root movement, atomic server changes, and
  exact idempotent replay. Ruff, mypy, Flutter analysis, and diff checks pass.
- `flutter test` passes with 259 tests after middle-page deletion and restore;
  the backend passes 54 unit/API tests and 15 PostgreSQL/MinIO integration
  tests. Alembic upgrades the development database and an independent empty
  database to `20260807_0014` with no schema drift. Focused tests cover delete
  queuing, position compaction, recovery metadata, and original-position restore.
- `flutter test` passes with 261 tests after explicit page-order synchronization;
  the backend passes 55 unit/API tests and 15 PostgreSQL/MinIO integration
  tests. Focused coverage proves durable full-order queuing, atomic server
  repositioning, stale-order rejection, cross-device application, and Cursor
  gating. Ruff, mypy, Flutter analysis, and diff checks pass.
- `flutter test` passes with 263 tests after infinite-canvas background
  synchronization; the backend passes 56 non-integration tests and 15 real
  PostgreSQL/MinIO integration tests. Focused coverage proves durable baseline
  mapping, upload queueing, legacy mapping repair, cross-device application,
  and stale-baseline rejection. Ruff, mypy, Flutter analysis, and diff checks
  pass.
- Full `flutter test` and `flutter analyze` pass after stable installation
  identity and new-device Merge repair. The backend passes 66 non-integration
  and 16 PostgreSQL/MinIO integration tests; Ruff, mypy, and diff checks pass.
  Alembic upgrades both the development database and an independent empty
  database to `20260810_0015` with no schema drift.
- Focused first-sign-in service and signed-in startup tests pass after local
  notebook creation repair, including initialized inventory discovery and an
  additional sync scheduled by notebook creation. `flutter analyze` and diff
  checks pass; no backend route or schema changed.

## Notes

- Backend code now lives under `server/` in the same repository as Flutter;
  its setup and validation commands are documented in `server/README.md`.
- Root `compose.yaml` defines the API, PostgreSQL 17, private MinIO storage,
  and idempotent bucket initialization; the local stack and dependency
  readiness have been confirmed.
- `lib/main.dart` now starts `InkNestApp`.
- App/theme code lives under `lib/app`.
- Library, notebook, and editor feature folders exist under `lib/features`.
- Library can create `Notebook 1` and navigate to an editor placeholder.
- Editor has a fixed white page canvas, captures pointer strokes, renders with `CustomPainter`, and supports undo/redo.
- Editor toolbar supports pen, highlighter, eraser, color choices, and width choices.
- File storage layout is documented in `docs/development/STORAGE.md`.
- Editor can add pages, switch pages, and persist each page independently.
- Library can import a PDF, copy it into notebook assets, create one note page per PDF page, and render the PDF page behind editable strokes.
- Editor can export the current notebook as a PDF, including blank pages, imported PDF page backgrounds, and handwriting strokes.
- Editor page viewport supports zoom controls and two-finger pinch/pan without saving accidental strokes.
- Editor redesign records live under
  `docs/product/features/editor-workspace-redesign/`; the implemented shell
  replaces permanent all-actions chrome with a document header, contextual
  tool dock, on-demand page navigator, and fixed document-coordinate viewport.
- Editor interaction polish records live under
  `docs/product/features/editor-workspace-polish/`; the floating page chip is
  removed, zoom chrome collapses by default, Fit Width/Fit Page are in More →
  View, and tool properties use an anchored popover on regular/wide widths.
- The current lowercase iOS bundle identifier uses a separate app container
  from the old mixed-case identifier; decide whether legacy prototype data
  must be recovered before implementing any coordinate conversion.
- Editor toolbar includes Finger pan mode; when enabled, touch drags the page and stylus input still writes.
- Editor toolbar includes default-on Finger assist; completed touch strokes are smoothed before saving while stylus and mouse strokes remain unchanged.
- Editor app bar includes a Page template picker for Blank, Ruled, Dotted, Grid, Cornell, and Planner pages; the selected template persists and appears in previews and PDF exports.
- Editor Pages panel shows page thumbnails with selection state, page numbers, handwriting previews, and PDF page markers on demand; wide layouts can pin it at the left, while Outline and Bookmarks open independently.
- Editor page thumbnails include actions to duplicate, delete with confirmation, and move pages left or right.
- Editor page thumbnail actions include clockwise page rotation; orientation persists, updates editor and page previews, keeps drawing hit testing aligned, and is preserved in PDF export.
- Editor toolbar includes Lasso; draw around strokes to select them, drag the selection to move it, drag its corner handle to resize proportionally, or use the upright floating toolbar to recolor, delete, and clear the selection.
- Editor app bar includes Import PDFs into notebook; it accepts multiple files, appends every imported page, preserves separate source assets and outlines, and opens the first new page when complete.
- Imported PDF pages retain their per-page source dimensions and orientation ratio through editor display, thumbnails, persistence, rotation, and PDF export.
- Editor strokes render with smoothed paths on canvas, thumbnails, and exported PDFs; the eraser can split strokes instead of only deleting whole strokes.
- Library notebook spines include rename, duplicate, archive/restore, and delete actions backed by repository persistence.
- Library supports creating root-level folders, moving notebooks into folders, entering folders, and deleting folders while moving contained notebooks back to the root library.
- Library supports visible search, notebook and folder sorting, folder/archive navigation, and gapless page-weighted spine rows without loading first-page cover previews.
- Library notebook spines briefly pull forward and scale before opening; long press, hover, or focus can hold inspection, and only truncated titles receive a full-title tip.
- Editor page thumbnails can insert blank pages before or after any page, including between imported PDF pages.
- Editor page thumbnails render PDF page backgrounds, and the editor has separate Outline and Bookmarks panels plus current-page bookmark toggling.
- Editor export can save the full notebook, current page, or an ordered page/range expression such as `1,3,5-7`, with filenames suffixed by exported scope.
- Editor export offers Compact, Balanced, and Best quality presets; Balanced is the default, Compact prioritizes sharing size, and Best preserves lossless PDF background detail.
- PDF export now avoids rerendering duplicate backgrounds in the same export and renders imported PDF backgrounds at a higher default pixel density.
- Editor toolbar includes a Text tool that can add typed text boxes to the current page; text boxes can be edited, moved, deleted, persisted, shown in thumbnails, and exported to PDF.
- Text boxes can toggle between regular text and handwriting-style rendering; thumbnails and PDF export use the same text style path.
- The Lasso contextual toolbar exposes Smart Ink for selected strokes, confirms text, and creates editable handwriting-style text from the selection.
- Editor toolbar includes Insert image; selected images are copied into notebook assets, placed on the current page, movable, resizable, deletable, persisted, shown as thumbnail placeholders, and included in PDF export.
- Editor toolbar includes a Shape tool with a shape-type menu for line, arrow, rectangle, and ellipse; created shapes persist, appear in thumbnails, and export to PDF.
- Editor tool dock includes complete black/teal/red pen and yellow highlighter presets without covering the paper.
- Saved recordings can be played, paused, scrubbed, and closed from the editor; all ink stays visible while the current recorded segment receives a temporary spotlight.
- Audio playback follows linked pages by default; manually selecting a page suspends following, and the playback bar can resume it.
- Editor app bar includes unified notebook search across cached PDF text, typed text boxes, and confirmed Smart Ink text, with cross-page navigation and source-specific highlighting.
- Smart Ink now sends selected vector strokes to ML Kit Digital Ink on iOS and
  Android, asynchronously prefills the confirmation field, and preserves manual
  entry when model download, recognition, or the plugin is unavailable.
- Smart Ink planning lives in `docs/development/SMART_INK_PLAN.md`.
- Handwriting recognition, scanned-page OCR, caching, and iPadOS 27 PencilKit follow-up decisions live in `docs/development/RECOGNITION_OCR_SPIKE.md`.
- Post-MVP feature gaps and optimization areas are documented in `docs/development/POST_MVP_ROADMAP.md`.
- Subscription packaging, platform behavior, and local/cloud merge rules are documented in `docs/development/SUBSCRIPTION_PLAN.md`.
- The accepted custom Python/PostgreSQL/MinIO backend scope is recorded under
  `docs/product/features/inknest-cloud-backend/`; the phased same-repository
  implementation plan lives in `docs/development/BACKEND_IMPLEMENTATION_PLAN.md`.
- Backend delivery can be resumed explicitly with `$inknest-backend`; the
  Skill reads the plan and status, selects one verified slice, and updates the
  durable records after implementation.
- Web knowledge-base, mobile companion, collaboration, and AI directions are captured as later post-MVP milestones.
- Graduation task book and opening report Markdown drafts live in `docs/academic/GRADUATION_TASK_BOOK.md` and `docs/academic/OPENING_REPORT.md`; maintain them with `$inknest-academic-docs`, not as an automatic side effect of development tasks.
- Python details in the graduation docs are described as formal module design, interface planning, and extension scope; implementation-specific project details should be added when available.
- Graduation docs now include clearer scope boundaries, acceptance indicators, technical route, feasibility analysis, expected deliverables, and Python extension placeholders.
- Docs are organized by purpose: `docs/development/` for project execution, `docs/academic/` for graduation materials, and `docs/learning/flutter/` for Flutter study notes.
- Academic writing requirements extracted from the task book and opening report guidance PDFs live in `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md`.
- Graduation task book and opening report now separate required Flutter deliverables, conditional audio/search enhancements, and Python extension design to reduce review-scope risk.
- 2026 summer adult-education graduation schedule image lives in `docs/academic/assets/2026_summer_graduation_schedule.png` and is embedded in both academic progress plans.
- Task book writing requirements in `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md` were rechecked against `/Users/lvyanxiang/Downloads/任务书撰写注意点.pdf`.
- Opening report writing requirements in `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md` were rechecked against `/Users/lvyanxiang/Downloads/开题报告撰写注意点.pdf`.
- Graduation task book and opening report should use formal wording such as Python module design, interface planning, and extension design, while avoiding internal phrases like "project not yet supplemented" or "retain topic rationality" in the submit-ready text.
- Formal graduation references should prioritize academic journal papers whose journal titles can be found through the school library journal navigation page; arXiv and official framework docs are auxiliary materials, not main formal references.
- Formal graduation references now require both journal-title availability and citation-year coverage in the school library journal navigation holdings; entries outside the covered years should be replaced or kept only as backup materials.
- Graduation references were refreshed on 2026-07-01: the task book uses 6 papers from 2024-2025, the opening report uses 10 papers from 2022-2025, and every listed paper has a corresponding body citation.
- Reference verification records, DOI values, school-library detail identifiers, and holdings coverage years are maintained in `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md`.
