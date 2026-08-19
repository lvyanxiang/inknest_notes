# Local Content Recognition Product Brief

- Status: Smart Ink retained; editor content search and raster OCR removed
- Size: Medium scope revision
- Updated: 2026-08-18
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md`

## Problem

The editor-internal Search feature added permanent document-bar chrome and a
large PDF/image OCR indexing subsystem that is no longer part of the accepted
editor workflow. Keeping its UI, caches, native dependencies, and tests would
create maintenance cost without an active product entry point.

## Accepted Outcome

Remove editor content search as one complete capability. Retain the lightweight
library search for notebook titles and root-folder names. Retain Smart Ink as an
explicit lasso action backed by ML Kit Digital Ink on both iOS and Android.

## Scope

- Remove the editor Search button and Search sheet.
- Remove PDF, inserted-image, and editable-text-box search services.
- Remove result navigation and PDF/image/text-box highlight behavior.
- Remove raster OCR contracts, derived OCR cache writers, ML Kit Text
  Recognition Flutter/native dependencies, and their tests.
- Keep `pdfrx` for PDF import, display, metadata inspection, and export.
- Keep ML Kit Digital Ink recognition, language-model fallback, manual text
  correction, fixed-layout redraw, and undo/redo for Smart Ink.
- Keep library search behavior unchanged.

## Non-goals

- No replacement editor search flow.
- No migration or deletion of previously generated disposable
  `derived/recognition` cache files.
- No change to notebook/page JSON or existing user content.
- No change to infinite-canvas search, which had no active entry point.

## Acceptance Criteria

- [x] No Search action or search state remains in the paged editor.
- [x] No PDF/image/text-box search result, navigation, or highlight code remains.
- [x] `google_mlkit_text_recognition` and explicit Chinese Text Recognition
  native dependencies are absent from Flutter, iOS, and Android configuration.
- [x] Search/OCR implementation files and dedicated tests are removed.
- [x] Library title/folder search remains available.
- [x] Smart Ink still uses ML Kit Digital Ink on both platforms and preserves
  manual recovery, fixed-layout redraw, and history behavior.
- [x] Existing notebook data remains readable without migration.

## Risks And Recovery

Users can no longer search inside an open notebook, including selectable PDF
text, typed text boxes, scanned pages, or inserted images. This is an explicit
scope reduction. Previously generated OCR sidecars are disposable and ignored;
leaving them in place avoids destructive filesystem migration.

## Delivery

- UI/UX spec: `docs/product/features/local-content-recognition/UI_UX_SPEC.md`
- Supersedes the 2026-08-17 editor OCR/search portion of this feature.
- Physical-device QA now applies only to ML Kit Digital Ink Smart Ink.
