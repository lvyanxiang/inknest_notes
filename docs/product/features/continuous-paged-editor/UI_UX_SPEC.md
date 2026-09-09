# Continuous Paged Editor UI/UX Specification

- Status: Delivered
- Updated: 2026-09-08
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Paged editor viewport, page header, zoom, page navigation,
  and finger input mode

## Recommendation

Use the same vertical continuous-sheet workspace on phones and tablets. Keep
the toolbar fixed while paper sheets scroll beneath it, separated by a quiet
workspace gap. Do not stretch paper to the screen's height or change document
coordinates to match the device aspect ratio.

## Primary Flow

1. Open New notebook. In the Paged notebook section, optionally change
   orientation, then tap an A4, Letter, or Digital 3:4 paper card to create and
   open a blank notebook immediately. No paper card is preselected; orientation
   starts in portrait.
2. Open a paged notebook in Fit Width with Page 1 near the top of the viewport.
3. Write with a stylus or drag one finger to scroll through adjacent sheets.
4. As the viewport focus crosses a page boundary, update the header page count,
   undo/redo target, bookmark state, and current-page actions.
5. Tap the labelled Pages icon, or use a visible Outline, Bookmarks, or More
   action; selecting an item scrolls its sheet into view.
6. Tap Add page, choose A4, Letter, or Digital 3:4, choose portrait or
   landscape, then tap a paper style. The page is created, selected, and
   scrolled into view.
7. The next Add page sheet reuses the latest size and orientation selected in
   this editor session.

## States And Feedback

| State | Visible behavior | Recovery |
|---|---|---|
| Loading | Current sheet appears first; unloaded sheets use quiet placeholders | Pages fill in without replacing the editor |
| Fit Width | Each rotated sheet fits the available width | Pinch or More → View zoom changes the shared scale |
| Custom zoom | Sheets enlarge together and can pan horizontally | Fit Width restores the reading flow |
| Scrolling | Header page number follows the sheet nearest the viewport focus | Page panel can jump precisely |
| Finger moves | One finger scrolls; stylus edits the active sheet | Switch to Finger writes for touch ink |
| Finger writes | Touch edits the active sheet; one-finger list scrolling is suspended | Header/Pages navigation remains available |
| Protected page | Current protected-page message remains visible; scrolling continues | Navigate to another page |
| Add page | Size chips, orientation toggle, and template grid | Closing cancels without creating a page; tapping a template confirms all selections |
| New notebook | Paged section with orientation toggle and three compact paper cards; separate Infinite canvas card | Closing cancels; tapping a paper or Infinite canvas creates and opens immediately |

## Layout

- Keep 16dp minimum horizontal workspace inset and a 20–24dp vertical gap
  between sheets.
- Center sheets when narrower than the viewport; when zoomed wider, expose
  horizontal panning without changing their document size.
- Build only visible and nearby pages. The current page remains the sheet
  nearest the viewport's reading focus.
- Keep the scrolling paper list free of persistent zoom controls. Show only a
  temporary centered percentage badge after zoom or Fit actions.
- Preserve the existing fixed header, editing dock, audio bars, navigator, and
  lasso toolbar.
- Remove previous/next arrows, the visible title/page subtitle, and the separate
  page-count control. Keep one 44dp Add page button and one 44dp icon-only Pages
  button that opens navigation. Put Pages first in the right-aligned document
  action group.
- Use exactly two fixed 52dp rows at every width: the document row and the
  drawing toolbar. The document row has one prioritized action list in this
  order: Add page, Undo, Redo, Outline, Bookmarks, Record, Export. A simple
  width-based capacity determines how many are shown directly; all remaining
  actions stay in More. A direct Fit Width action stays immediately before
  More. Header icons use a compact 20dp visual inside a 44dp touch target. The
  Pages icon always opens Pages, and the optional pinned Pages rail remains
  available at 1100dp and above.
- At widths below 360dp, the drawing row may scroll horizontally within its
  fixed 52dp height so every core drawing tool remains reachable without
  changing the editor chrome height.
- The Add page sheet presents A4, Letter, and Digital 3:4 as size chips;
  portrait/landscape use one two-option segmented control. Template previews
  reflect the selected aspect ratio. It defaults to the current recognized
  notebook paper, with A4 portrait as fallback.
- The single New notebook sheet shows three compact aspect-ratio previews inside
  Paged notebook and one orientation toggle. Tapping a paper card creates a
  blank notebook directly; Infinite canvas remains a separate direct card.

## Input And Accessibility

- Default paged notebooks to Finger moves so scrolling is immediately
  discoverable. Stylus and inverted stylus are never page-scroll drag devices.
- Finger writes disables one-finger list scrolling to prevent simultaneous ink
  and viewport motion. Pinch still cancels partial ink before zooming.
- Mouse wheel and trackpad scroll vertically; Zoom out/in remain available in
  More → View, while Fit Width is a labelled direct header action.
- Each sheet is a semantic region labelled `Page n of total`; the Pages panel
  remains a non-gesture route to every page.
- Paper-size chips and portrait/landscape controls remain labelled and
  keyboard-focusable; selecting a template confirms the current setup.
- New-notebook paper cards expose size, orientation, and physical dimensions in
  semantics. They use normal button states only, with no selected/default
  treatment.

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
      available, and the icon-only Pages action has a current-page semantic
      label.
- [x] Page rotation is absent from the Pages panel and thumbnail action menus;
      previously rotated pages remain viewable.
- [x] Add page offers A4, Letter, and Digital 3:4 independently from template
      style, in portrait and landscape.
- [x] New notebook requires one sheet only: each Paged paper card and the
      Infinite canvas card creates immediately.
- [x] No new-notebook paper card appears selected before activation; Add page
      still initially matches the created notebook paper.
- [x] New notebooks default to A4 portrait, while existing and imported PDF
      page dimensions remain unchanged.
- [x] 390dp, 600dp, 834dp, and 1194dp layouts use two fixed 52dp editor rows;
      no third navigation row is rendered.
- [x] The ordered action capacity shows Add page directly at every width and
      exposes overflow actions in More without horizontal or vertical toolbar
      overflow.
- [x] No persistent zoom control covers scrolling paper; Zoom out and Zoom in
      remain in More → View, while one Fit Width reset is directly available in
      the header.

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
- Every width now uses the same two-row chrome. The document row applies one
  ordered action-capacity rule: Add page, Undo, Redo, Outline, Bookmarks,
  Record, Export. Actions beyond the width capacity remain in More, while the
  icon-only Pages action continues to open Pages.
- Persistent paged-paper zoom chrome was removed on 2026-09-08. Pinch remains
  the primary touch path, More → View provides Zoom out and Zoom in, Fit Width
  is a compact direct header action, and a transient percentage badge confirms
  every applied action.
