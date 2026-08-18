# Local Content Recognition Product Brief

- Status: Implemented; physical-device recognition QA pending
- Size: Large
- Updated: 2026-08-18
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` Advanced Capabilities

## Problem

Before this delivery, InkNest could search selectable PDF text and editable text
boxes, but scanned pages and inserted images were invisible to search. Smart
Ink also rasterized selected strokes through an Apple-only Vision bridge, so
recognition was not a coherent iOS/Android capability.

## Recommended Outcome

Create one local-first recognition domain with separate vector-ink and raster
text providers. Use Google ML Kit on both mobile platforms: Digital Ink for
InkNest stroke data and Text Recognition for images and scanned PDF pages.
For PDF search, use `pdfrx` first and invoke ML Kit only when a page has no
usable selectable text. Store automatic recognition as disposable local
sidecar data so engine upgrades never mutate notebook content or create sync
conflicts.

## Scope

- In scope:
  - A shared Flutter-facing raster OCR contract backed by
    `google_mlkit_text_recognition` on iOS and Android.
  - Text-layer-first PDF search with `pdfrx` and per-page ML Kit fallback.
  - Persistent, fingerprinted, versioned local OCR entries with page-space
    highlight regions.
  - Partial search results, progress, failure reporting, and retry-safe cache
    invalidation.
  - Inserted-image OCR in paged-notebook search, with page-space highlights and
    versioned local cache invalidation.
  - ML Kit Digital Ink recognition for selected Smart Ink strokes on iOS and
    Android, with lazy model download and manual text correction fallback.
  - Fixed-layout Smart Ink redraw: replacement glyph ink must remain within the
    selected strokes' original painted bounds so neighboring handwriting keeps
    its position and spacing.
- Non-goals:
  - Cloud OCR, server-side indexing, or syncing automatic OCR results.
  - Full-library search outside the open notebook.
  - Automatic whole-page handwriting recognition or background recognition of
    every saved stroke.
  - Infinite-canvas image search until that editor has a search entry point.
  - Syncing downloaded ML Kit models or derived recognition output.

## User Flow

1. The user opens Search in a notebook and enters a query.
2. InkNest reads selectable PDF text. Pages without usable text are rendered at
   a bounded resolution and recognized locally with ML Kit.
3. Search returns available matches immediately after processing, labels OCR
   progress, and highlights the matching page region when selected.
4. A failed page remains searchable through other sources and can be retried on
   the next search without changing the notebook.
5. Inserted images are indexed through the same raster provider and appear as
   `Image text` results that jump to and highlight the recognized region.
6. Smart Ink sends selected vector strokes to ML Kit Digital Ink. On first use,
   required language models download; recognized text prefills the existing
   confirmation dialog and remains editable before replacement.

## Acceptance Criteria

- [x] Selectable-text PDF pages use `pdfrx` and are not redundantly OCRed.
- [ ] A scanned PDF page is rendered, recognized on device, and searchable on
  both iOS and Android through the same Flutter provider contract.
- [ ] OCR highlight rectangles map from rendered-image coordinates into the
  persisted notebook page coordinate space, including rotated pages.
- [x] Successful OCR survives app restart while a PDF byte change, OCR schema
  change, engine change, or language/script change invalidates the entry.
- [x] Missing models, empty recognition, corrupt PDFs, cancellation, and page
  failures do not change or block local notebook editing.
- [x] Existing notebooks and selectable-PDF search remain compatible.
- [x] Inserted images are recognized with ML Kit Text Recognition, cached by
  source fingerprint and engine version, searchable, and highlighted in page
  coordinates without mutating `NoteImage` or page JSON.
- [x] Smart Ink uses ML Kit Digital Ink on both iOS and Android and no longer
  invokes Apple Vision or rasterizes strokes for recognition.
- [x] Digital Ink converts each stored stroke and point timestamp without
  changing the original ink; model download, unavailable network/model, empty
  candidates, and plugin failure retain manual text entry.
- [x] Smart Ink redraw never expands the original selection bounds, never
  auto-wraps a single-line selection, and includes glyph overhang plus generated
  stroke width when fitting every bundled handwriting font.

## Alternatives And Tradeoffs

- Apple Vision on iOS plus ML Kit on Android: avoids ML Kit iOS size cost but
  retains two raster engines and two native response contracts; rejected for
  the accepted dual-platform baseline.
- ML Kit on every PDF page: simpler branching but wastes battery and produces
  duplicate or lower-quality text when a source text layer already exists.

## Dependencies And Risks

- `google_mlkit_text_recognition` requires an iOS 15.5 deployment target and
  native Chinese-script dependencies.
- The Flutter bridge is community maintained; InkNest must own a stable
  provider contract and deterministic tests around it.
- OCR can be expensive on large scanned documents. Work must be bounded,
  sequential, cancellable, and kept off the handwriting-critical path.
- OCR output varies with native ML Kit releases, so cache identity includes an
  InkNest schema/engine key and remains derived data.

## Open Decisions

- None. The accepted default handwriting languages are Simplified Chinese and
  US English; candidates remain user-correctable because model scores and
  handwriting ambiguity cannot guarantee the intended language.

## Delivery

- UI/UX spec: `docs/product/features/local-content-recognition/UI_UX_SPEC.md`
- Implementation status: PDF OCR, inserted-image OCR, and Digital Ink Smart Ink
  are implemented. The Apple Vision bridge and rasterized-ink OCR path are
  removed.
- Verification: Layering, coordinate mapping, cache persistence/invalidation,
  existing PDF search, and notebook search tests pass. `flutter analyze`, the
  full Flutter test suite, iOS simulator build, and Android debug APK build
  pass. Physical iOS and Android OCR quality, rotation, memory, cancellation,
  and latency QA remain required before release. Digital Ink vector/timestamp
  conversion, locale fallback, model failure, image decoding/cache reuse,
  unified image search presentation, and manual Smart Ink recovery are covered
  by automated tests; both native debug builds pass.
  Fixed-layout redraw tests cover every bundled handwriting font, long
  single-line text, explicit multi-line text, painted glyph bounds, and the
  lasso selection bounds.
- Toolchain note: ML Kit currently requires CocoaPods on iOS. Android is pinned
  to AGP 8.13 until the current Flutter plugins support AGP 9 Built-in Kotlin.
