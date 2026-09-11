# Local Content Recognition UI/UX Specification

- Status: Editor search removed; Smart Ink retained
- Updated: 2026-09-11
- Product brief: `docs/product/features/local-content-recognition/PRODUCT_BRIEF.md`
- Affected surfaces: Editor document bar, page surface, and Smart Ink dialog

## Recommendation

Remove Search from the paged editor as a complete interaction rather than
leaving a disabled control or hidden sheet. Reclaim the document-bar space for
the notebook context and existing history/audio/export actions. Do not add a
replacement menu item. Preserve the existing library Search and lasso-context
Smart Ink paths.

## Resulting Flow

1. Opening a paged notebook shows no editor Search action at any width.
2. PDF pages, inserted images, and text boxes render without search overlays.
3. Manual page navigation only affects normal page and audio-follow state.
4. Lassoing handwriting still exposes Smart Ink.
5. Tapping handwriting while Lasso is active selects its spatially connected
   handwriting block and exposes the same selection toolbar. Recognition does
   not start until the user chooses Beautify.
6. Smart Ink prepares ML Kit Digital Ink recognition, allows correction or
   manual entry, and redraws inside the fixed original selection bounds.

## State And Layout

- Removed states: Search sheet, query, indexing progress, empty/error results,
  selected result, cross-page jump, and search highlight.
- Document bar: surrounding actions close the removed Search gap using the
  existing responsive `AppBar` layout.
- Page surface: no PDF/image highlight layer and no text-box search decoration.
- Accessibility: no stale Search tooltip, semantics node, focus target, or
  keyboard route remains.
- Smart Ink: current busy, ready, failure, cancel, confirm, and undo/redo states
  remain unchanged. Opening the editor starts a non-blocking, best-effort
  preload of the locale's primary and fallback handwriting models. No progress
  dialog interrupts writing. Already-downloaded language models are attempted
  before a missing fallback model; the first usable result ends the busy state
  without waiting for another model download. Model preparation and
  recognition have bounded waits, after which the existing manual-entry
  recovery remains available.
- Lasso tap: select the connected handwriting block nearest the tap. Prefer
  horizontal expansion along one line; do not normally include clearly
  separated words or adjacent lines. Keep drag-lasso selection unchanged.

## UI Acceptance Criteria

- [x] `Search notebook` is absent from the editor document bar.
- [x] No search sheet can be opened from editor chrome or overflow menus.
- [x] Page navigation and audio-follow behavior no longer reference search
  state.
- [x] Text boxes use only their normal editing decoration.
- [x] Library `Search notebooks` remains visible and unchanged.
- [x] Smart Ink remains accessible from a lasso selection and does not add
  permanent editor chrome.
- [x] Entering the editor prepares the current language models in the
  background so the first recognition normally performs no model download.
- [x] Tapping handwriting with Lasso active frames its connected handwriting
  block and shows Beautify without launching recognition automatically.

## Verification

- Widget coverage asserts the editor Search action is absent while the library
  search field remains covered by its existing filtering tests.
- Full Flutter tests and static analysis guard Smart Ink, PDF rendering/import,
  text boxes, images, page navigation, and responsive editor chrome.
