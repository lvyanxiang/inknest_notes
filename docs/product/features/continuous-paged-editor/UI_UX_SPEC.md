# Continuous Paged Editor UI/UX Specification

- Status: Delivered
- Updated: 2026-09-07
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Paged editor viewport, page header, zoom, page navigation,
  and finger input mode

## Recommendation

Use the same vertical continuous-sheet workspace on phones and tablets. Keep
the toolbar fixed while paper sheets scroll beneath it, separated by a quiet
workspace gap. Do not stretch paper to the screen's height or change document
coordinates to match the device aspect ratio.

## Primary Flow

1. Open a paged notebook in Fit Width with Page 1 near the top of the viewport.
2. Write with a stylus or drag one finger to scroll through adjacent sheets.
3. As the viewport focus crosses a page boundary, update the header page count,
   undo/redo target, bookmark state, and current-page actions.
4. Tap the title's `Page n of total`, Outline, or Bookmarks to jump directly;
   the selected sheet scrolls into view.
5. Adding or duplicating a page selects it and scrolls it into view.

## States And Feedback

| State | Visible behavior | Recovery |
|---|---|---|
| Loading | Current sheet appears first; unloaded sheets use quiet placeholders | Pages fill in without replacing the editor |
| Fit Width | Each rotated sheet fits the available width | Zoom or Fit Page changes the shared scale |
| Custom zoom | Sheets enlarge together and can pan horizontally | Fit Width restores the reading flow |
| Scrolling | Header page number follows the sheet nearest the viewport focus | Page panel can jump precisely |
| Finger moves | One finger scrolls; stylus edits the active sheet | Switch to Finger writes for touch ink |
| Finger writes | Touch edits the active sheet; one-finger list scrolling is suspended | Header/Pages navigation remains available |
| Protected page | Current protected-page message remains visible; scrolling continues | Navigate to another page |

## Layout

- Keep 16dp minimum horizontal workspace inset and a 20–24dp vertical gap
  between sheets.
- Center sheets when narrower than the viewport; when zoomed wider, expose
  horizontal panning without changing their document size.
- Build only visible and nearby pages. The current page remains the sheet
  nearest the viewport's reading focus.
- Keep zoom controls viewport-fixed, upright, and above the paper list.
- Preserve the existing fixed header, editing dock, audio bars, Pages panel,
  and lasso toolbar.
- Remove previous/next arrows and the separate page-count control. Keep one
  44dp Add page button beside Outline and Bookmarks. Treat the title and page
  subtitle as one labelled button that opens Pages.

## Input And Accessibility

- Default paged notebooks to Finger moves so scrolling is immediately
  discoverable. Stylus and inverted stylus are never page-scroll drag devices.
- Finger writes disables one-finger list scrolling to prevent simultaneous ink
  and viewport motion. Pinch still cancels partial ink before zooming.
- Mouse wheel and trackpad scroll vertically; zoom controls remain keyboard and
  semantics-accessible alternatives to pinch.
- Each sheet is a semantic region labelled `Page n of total`; the Pages panel
  remains a non-gesture route to every page.

## UI Acceptance Criteria

- [x] 390×844, 600×800, 834×1194, and 1194×834 layouts show a continuous list
      without toolbar overflow or altered page coordinates.
- [x] Scrolling between two pages updates `n / total` and current-page actions.
- [x] A direct page jump positions the requested sheet in the viewport.
- [x] Stylus drawing, touch scrolling, Finger writes, and pinch zoom have one
      owner each and never create accidental ink.
- [x] Rotated and differently sized sheets remain centered, separated, and
      editable.
- [x] Large text and screen readers retain labelled page navigation controls.
- [x] No previous/next page arrows remain; Add page is still directly
      available, and the document context opens Pages with a clear semantic
      label.

## Verification

- Responsive widget tests for phone portrait, tablet portrait, tablet
  landscape, scrolling, page jumps, drawing coordinates, and gesture ownership.
- Existing editor and complete Flutter regression suite plus `flutter analyze`.

## Implementation Review

- Status: Delivered
- The previous one-page viewport was replaced by one lazy vertical list with
  shared Fit Width-relative zoom. Adjacent-page buttons were removed because
  scrolling is now the primary navigation; the visible page position and Pages
  panel provide the accessible precision-jump fallback.
