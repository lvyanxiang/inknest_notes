# Handwriting Recognition And OCR Spike

Date: 2026-07-18

## Outcome

Use two local-first Apple recognition paths behind one Flutter-facing result
model:

- Use Vision text recognition for raster OCR on selected Smart Ink strokes,
  scanned PDF pages, inserted images, and future camera scans.
- Prefer PencilKit `PKStrokeRecognizer` for vector handwriting recognition,
  indexing, and search when InkNest is built with the iPadOS 27 SDK and the
  device runs iPadOS 27 or later.
- Keep manual Smart Ink confirmation available on every platform and never
  delete selected strokes before the user confirms replacement.

This does not raise the current iOS 13 deployment target. The repository is
currently built with Xcode 26.5, so the iPadOS 27 PencilKit integration must
remain availability-gated until an SDK containing `PKStrokeRecognizer` is
adopted.

## Official Capability Findings

- Apple Vision performs text recognition on device and supports fast and
  accurate paths. InkNest uses the accurate path for asynchronous note OCR:
  <https://developer.apple.com/documentation/vision/recognizing-text-in-images>
- Vision exposes recognized text, confidence, normalized bounds, supported
  languages, language priority, and optional language correction:
  <https://developer.apple.com/documentation/vision/vnrecognizetextrequest>
- Simplified/traditional Chinese should be prioritized explicitly, and Apple
  documents limitations around Chinese language correction and bounding-box
  granularity.
- iPadOS 27 adds on-device PencilKit handwriting recognition over an entire
  drawing or selected stroke IDs, plus indexable content and text search with
  bounds:
  <https://developer.apple.com/documentation/pencilkit/recognizing-handwriting-and-converting-to-text>

## Implemented Spike Baseline

- `TextRecognitionProvider` separates Flutter editor code from the native
  engine and returns text, confidence, normalized regions, and an engine ID.
- `InkRecognitionImageRenderer` converts selected InkNest strokes to a padded,
  black-on-white PNG capped at 2048 pixels on its longest edge.
- The iOS app registers an Apple Vision method channel, filters requested
  languages against those supported by the active Vision revision, and runs
  accurate recognition off the main thread.
- Smart Ink starts recognition without blocking editing, prefills the
  confirmation field when a result arrives, and falls back to manual input for
  missing plugins, empty results, or recognition failures.
- Initial language priority is simplified Chinese followed by US English.

## Search Integration Direction

The same provider result can support scanned-PDF and image search in a later
implementation step:

1. Render a source PDF page with `pdfrx` or decode an inserted image.
2. Run Vision OCR at a bounded resolution in a cancellable background queue.
3. Convert normalized top-left OCR regions to notebook-page coordinates.
4. Cache text and regions by source fingerprint, page number, language set,
   engine identifier, and OCR schema version.
5. Merge OCR entries with the existing embedded PDF text index while avoiding
   duplicate text when a selectable text layer already exists.

OCR indexing should be lazy, persistent, and invalidated only when the source
or recognition engine version changes. Recognition data stays on device unless
a future cloud provider is explicitly enabled and disclosed.

## PencilKit 27 Follow-up

When the build environment adopts the iPadOS 27 SDK:

1. Convert InkNest stroke paths to `PKStroke`/`PKDrawing` while retaining a
   mapping from InkNest stroke IDs to PencilKit stroke IDs.
2. Add a provider that calls `PKStrokeRecognizer` for selected-stroke Smart Ink.
3. Use PencilKit indexable content and bounded search for handwriting search.
4. Keep Vision as the OCR path for scanned pages and images and as a pre-iPadOS
   27 best-effort Smart Ink fallback.
5. Compare Chinese/English accuracy, latency, memory, and line-order behavior
   on physical iPad hardware before making PencilKit results automatic.

## Acceptance And Risk Notes

- Recognition failure never changes the page or removes ink.
- User edits win if recognition finishes after the user starts typing.
- Native output coordinates use a normalized, top-left-origin contract so
  future PDF/image highlight mapping is deterministic.
- The current Vision path is an OCR fallback for rasterized handwriting; it is
  not presented as equivalent to the iPadOS 27 handwriting-specific model.
- Automated Dart tests cover request mapping, normalized result geometry,
  bounded PNG rendering, and Smart Ink suggestion prefilling.
- `flutter build ios --simulator --no-codesign` verifies the native Vision
  bridge with Xcode 26.5 and the current iOS 13 deployment target.
