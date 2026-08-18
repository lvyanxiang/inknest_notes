# Local Content Recognition UI/UX Specification

- Status: Implemented; physical-device review pending
- Updated: 2026-08-18
- Product brief: `docs/product/features/local-content-recognition/PRODUCT_BRIEF.md`
- Affected surfaces: Notebook search sheet, search highlights, and Smart Ink
  confirmation dialog

## Recommendation

Keep OCR implicit inside the existing notebook search flow. Search should show
useful partial results and bounded progress without adding permanent editor
chrome or interrupting Pencil input. OCR is described as indexing, not as an
engine choice.

## User Flow

1. Open the existing notebook Search sheet and type a query.
2. The sheet searches editable text and selectable PDF text while locally
   indexing scanned pages that have no usable text layer.
3. It shows `Indexing scanned page X of Y…` while work remains and then renders
   OCR results in the same result list.
4. Selecting a result closes the sheet, navigates to the page, and highlights
   the recognized region. Closing Search cancels UI updates but does not damage
   a successfully written cache entry.
5. Image OCR results use the same list and jump behavior with the source label
   `Image text`.
6. Smart Ink keeps the existing lasso action and confirmation dialog. It shows
   `Preparing handwriting recognition…` while ML Kit checks or downloads its
   model, then prefills editable recognized text. Failure reveals manual entry
   without changing the selected strokes.
7. Confirming Smart Ink redraw uses the selected strokes' existing painted
   bounds as a fixed container. The chosen font scales uniformly inside it;
   neighboring strokes, selection position, and available line spacing do not
   move or expand.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Default | Existing Search field and guidance covering PDF and editable text | Type, submit, close | No OCR-specific control |
| Busy | Linear progress and scanned-page progress label | Close, edit query | Existing partial sources remain safe |
| Ready | Unified result rows | Select result, refine query | OCR result navigates and highlights like PDF text |
| Empty | No searchable text message | Edit query, close | Explain when pages could not be indexed |
| Error | Non-blocking count of unavailable pages | Retry by searching again | Other results remain available |
| OCR unavailable | Searchable non-OCR sources remain visible | Close, edit query | Explain local text recognition is unavailable |
| Digital Ink preparing | Existing Smart Ink dialog with bounded progress | Cancel | Selected strokes stay unchanged |
| Digital Ink ready | Recognized text preview and existing style choices | Confirm, edit, cancel | Text remains editable before redraw |
| Digital Ink failure | Manual text field and concise recovery copy | Type manually, cancel | No stroke replacement until confirmation |

## Layout And Components

- Placement and hierarchy: reuse the current 78%-height Search sheet, search
  field, linear progress indicator, result list, and highlight layer.
- Reused components: `NotebookTextSearchSheet`, `_SearchMessage`, existing PDF
  result row, and `PdfSearchHighlightLayer`.
- New component or pattern: none in the first slice; extend progress and source
  status in the existing response model.
- User-facing copy:
  - Empty hint: `Search PDF, images, scanned pages, and editable text`
  - OCR progress: `Indexing scanned page X of Y…`
  - Partial failure: `Some scanned pages could not be indexed.`
  - Image source: `Image text`
  - Smart Ink busy: `Preparing handwriting recognition…`

## Input And Responsive Behavior

- Pencil and touch: opening or closing Search never changes the active editor
  tool, selection, or page content.
- Mouse/trackpad and keyboard: preserve current field focus, Enter-to-search,
  clear, close, and result activation behavior.
- iPad portrait/landscape or split view: retain the current sheet constraints;
  progress copy must wrap without hiding Close or the query field.
- Phone/Web: Android phone uses the same mobile sheet. Web is out of scope
  because ML Kit mobile APIs do not support it.
- Smart Ink layout: preserve explicit line breaks, never introduce wrapping,
  render with overhang padding, measure actual raster ink, and contain the
  complete generated painted stroke bounds inside the original selection.

## Accessibility

- Semantics and focus: progress updates have readable text; result source and
  page number remain in the accessible row label.
- Text scaling and contrast: use theme typography and progress colors; allow
  status copy to wrap.
- Non-gesture alternative: Search remains available through its existing
  button and keyboard flow; no OCR-only gesture is introduced.

## UI Acceptance Criteria

- [x] Search clearly reports PDF indexing without blocking editing.
- [x] Selectable PDF, editable text, and OCR matches use one result list and
  preserve the existing jump/highlight behavior.
- [ ] Empty, partial failure, unavailable model, and retry behavior are visible
  and non-destructive.
- [ ] The sheet remains usable at narrow split-view widths and enlarged text.
- [x] Inserted-image OCR results are distinguishable, navigate correctly, and
  highlight above the image without intercepting gestures.
- [x] Smart Ink uses the existing lasso and confirmation path on both mobile
  platforms; model preparation and errors never alter selected strokes.
- [x] Smart Ink replacement remains inside the original painted selection
  bounds for short, long, single-line, and explicit multi-line text across all
  bundled fonts; surrounding handwriting does not move.

## Verification

- Widget tests: busy, empty, OCR result, partial failure, close, and query
  generation behavior.
- Responsive/semantic/golden tests: focused responsive and semantics tests;
  no new golden is required for reused components.
- Manual device checks: large scanned PDF, rotation, cancellation, model setup,
  memory, and latency on physical iOS and Android devices.

## Implementation Review

- Status: Implemented; physical-device review pending
- Intentional deviations:
  - Search uses one `Indexing notebook content X of Y…` counter for PDF
    text-layer inspection, scanned-page OCR, and inserted-image OCR.
  - The current search service publishes the combined result list after PDF
    indexing finishes; progressive partial-result rendering remains follow-up
  polish. Closing or changing the query still suppresses stale UI updates.
  - Smart Ink redraw is stored as ordinary generated strokes rather than a
    persistent text container; both its painted bounds and its recomputed lasso
    bounds are contained inside the immutable source selection footprint.
