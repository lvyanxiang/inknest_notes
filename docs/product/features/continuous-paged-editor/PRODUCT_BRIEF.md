# Continuous Paged Editor

- Status: Delivered
- Size: Medium
- Updated: 2026-09-07
- Roadmap link: User-requested paged editor improvement

## Problem

The paged editor presents one fitted page at a time and makes adjacent-page
buttons the primary navigation. On tall phones this leaves the paper visually
detached from the rest of the notebook, while on tablets it interrupts reading
and writing across a page boundary.

## Recommended Outcome

Present every page in one vertically continuous, lazy list on phone and tablet.
Each sheet keeps its persisted dimensions, rotation, content coordinates, and
independent edit history. Scrolling changes the current page shown by the
header. Remove redundant previous/next toolbar buttons, keep Add page, and make
the visible `Page n of total` document context open the Pages panel for precise
navigation and management.

Keep the fixed editor chrome to two 52dp rows at every width. The document row
uses one ordered action list and a width-derived visible-action capacity; items
that do not fit move to More. Add page, undo, redo, outline, bookmarks,
recording, and export therefore share one responsive rule instead of separate
phone and tablet layouts.

Because a touch drag cannot both write and scroll, paged notebooks start in
`Finger moves`: one finger scrolls and a stylus writes. `Finger writes` remains
available as an explicit mode and disables one-finger page scrolling while it
is active.

## Scope

- In scope:
  - One vertical continuous-page layout for phones and tablets on iOS/iPadOS
    and Android.
  - Lazy page construction with a consistent workspace gap between sheets.
  - Fit Width as the initial scale for every sheet, shared notebook zoom, and
    horizontal panning when zoomed beyond the viewport.
  - Current-page tracking while scrolling and programmatic jumps from header,
    Pages, Outline, Bookmarks, audio follow, and page creation.
  - A simplified header with Add page as the only dedicated pagination action;
    the visible page position opens Pages for non-gesture navigation.
  - One two-row editor header at every width. The document row exposes a
    prioritized action list and moves overflow into More without toolbar
    wrapping.
  - Existing editing layers, canonical coordinates, rotation, persistence,
    undo/redo, protected-page state, and PDF backgrounds.
  - Explicit gesture ownership between finger scrolling, stylus writing,
    finger writing, and pinch zoom.
- Non-goals:
  - Changing stored page dimensions or notebook format.
  - Mixing infinite-canvas content into paged notebooks.
  - Two-page spreads, horizontal page flow, or freeform page rearrangement in
    the editor surface.
  - Persisting zoom and scroll position across app restarts.

## Acceptance Criteria

- [x] Two or more notebook pages are vertically stacked and reachable by
      scrolling on phone and tablet layouts.
- [x] Scrolling updates the header current-page number without unloading the
      notebook workspace.
- [x] Page navigation controls, thumbnails, bookmarks, outline, and audio
      follow scroll to the requested page.
- [x] New, duplicated, imported, or retained pages become visible at their
      requested position.
- [x] Every page keeps its canonical document size and coordinate mapping;
      drawing after scrolling or zooming saves inside that page.
- [x] Finger moves scrolls without creating ink; stylus writing does not drag
      the page list; Finger writes preserves touch drawing without simultaneous
      one-finger scrolling.
- [x] Fit Width, Fit Page, zoom in/out, rotation, erasing, selection, text,
      images, shapes, undo/redo, and write protection remain available.
- [x] The complete Flutter test suite and static analysis pass.
- [x] Previous/next toolbar buttons are absent; Add page remains a 44dp target,
      and activating `Page n of total` opens Pages.
- [x] At every supported width, the editor chrome occupies two 52dp rows; the
      prioritized document-row actions fit without wrapping, and overflow
      actions remain reachable from More.

## Risks

- Rendering every page eagerly would increase memory use for long PDF
  notebooks, so page widgets must remain lazily built.
- Current-page updates during scroll must not recursively trigger another
  animated jump.
- Nested vertical and horizontal scrolling must exclude stylus drags so Pencil
  input remains owned by the active page.

## Delivery

- UI/UX spec: `UI_UX_SPEC.md`
- Implementation status: Delivered
- Verification: `flutter analyze`; full `flutter test` suite (310 tests).
