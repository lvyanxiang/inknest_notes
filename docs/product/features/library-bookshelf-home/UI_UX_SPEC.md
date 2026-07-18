# Library Bookshelf Home UI/UX Specification

- Status: Accepted
- Updated: 2026-07-18
- Product brief: `docs/product/features/library-bookshelf-home/PRODUCT_BRIEF.md`
- Affected surfaces: Root library, folder library, archived library, library
  search results

## Recommendation

Use a modern, restrained bookshelf rather than a literal wooden illustration.
Each notebook is a portrait book cover with a subtle spine, first-page preview,
title, and page count. Equal-width books sit on a shared tonal shelf rail so the
collection reads as a library at a glance. Folder covers use the same footprint
but a distinct collection treatment. This keeps InkNest recognizable while
remaining compatible with the existing Material theme and controls.

## User Flow

1. Open the app, a folder, or the archive and scan shelf rows from left to right.
2. Tap anywhere on a book/folder cover to open it, or use its overflow control
   for secondary actions.
3. Search and sort update the books in place; results retain the shelf layout.
4. Clear search or navigate back to recover the preceding library context.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Loading | Existing centered progress indicator | Wait | Shelf appears after repository load |
| Populated | Responsive shelf rows with folders first, then notebooks | Open, search, sort, manage, create/import | Ink ripple and existing navigation/dialog feedback |
| Search | Search field plus matching shelf items | Edit/clear query, open/manage result | Clear returns to the full shelf |
| No results | Existing no-matches state and query | Clear or change query | Results repopulate in place |
| Empty | Existing library/folder/archive empty state | Create or import where allowed | Existing creation/import flow |
| Narrow/split view | One or two books per row depending on width | Same actions with touch-sized targets | Content scrolls vertically without horizontal clipping |

## Layout And Components

- Placement and hierarchy:
  - Keep the current app bar and optional search field.
  - Start the bookshelf directly below them; do not add a Recent section.
  - Center shelf content at large widths and keep adaptive outer padding.
  - Each shelf row has equal-width covers, consistent gaps, and one shared rail.
- Reused components:
  - Existing notebook thumbnail renderer, action menus, search field, dialogs,
    empty states, and app theme tokens.
- New component or pattern, if justified:
  - `LibraryBookshelf` lazy rows and a decorative `ShelfRail`.
  - Book-cover treatment with a spine accent and semantic whole-cover tap target.
- User-facing copy:
  - Remove `Recent notebooks`.
  - Keep current notebook titles, page-count copy, action tooltips, and sort labels.

## Input And Responsive Behavior

- Pencil and touch: Entire book/folder cover opens the item; overflow actions
  remain at least 44 logical pixels as an independent target.
- Mouse/trackpad and keyboard: Material focus, hover, splash, tooltip, and menu
  behavior remain available through `InkWell` and existing menu controls.
- iPad portrait/landscape or split view: Use adaptive one-to-five-column shelf
  rows with no horizontal scrolling; iPad portrait targets three or four books,
  landscape targets five at the bounded content width.
- Phone/Web, if in scope: Narrow widths collapse to one or two books. A broader
  platform-specific home redesign is outside this change.

## Accessibility

- Semantics and focus: Each whole cover is a named button (`Open notebook ...`
  or `Open folder ...`); overflow menus retain explicit action tooltips.
- Text scaling and contrast: Titles are single-line with ellipsis, metadata uses
  theme contrast colors, and the shelf is decorative rather than informational.
- Non-gesture alternative: Every tap interaction has a standard button/menu
  target; no drag or hidden gesture is required.

## UI Acceptance Criteria

- [x] Notebook and folder covers form visually continuous shelf rows.
- [x] Shelf columns adapt without overflow at narrow, portrait, landscape, and
  large widths.
- [x] Whole-cover open targets and overflow actions remain distinct and usable.
- [x] Search, loading, empty, archive, and folder states preserve clear feedback.
- [x] Recent sorting remains available while the duplicate Recent section is gone.

## Verification

- Widget tests: Update library search/sort/thumbnail coverage to assert the
  bookshelf and absence of the Recent section.
- Responsive/semantic/golden tests: Add a narrow-width bookshelf assertion and
  semantic open labels where practical.
- Manual device checks: Inspect iPad portrait and landscape shelf density,
  thumbnail legibility, and menu hit targets.

## Implementation Review

- Status: Complete
- Intentional deviations: None.
