# Library Bookshelf Home UI/UX Specification

- Status: Accepted
- Updated: 2026-07-18
- Product brief: `docs/product/features/library-bookshelf-home/PRODUCT_BRIEF.md`
- Affected surfaces: Root library, folder library, archived library, library
  search results

## Recommendation

Treat the full screen as one modern library room. A custom Library Header and
tonal command bar replace the old AppBar, using the same warm surface, border,
shadow, and accent language as the shelves. Below it, notebooks stand with
their spines facing the user and touch without an artificial layout gap. The
metaphor
is physical, but restrained: no wood texture, ornamental rendering, or fake
perspective.

## User Flow

1. Open the app and identify the current location from the header: My Library,
   a folder name, or Archived.
2. Use the always-visible search field, labelled sort control, folder button,
   or archive button without opening an extra search mode.
3. Tap a book/binder spine to open it, or use the bottom overflow control for
   management actions.
4. Clear search or use the header back control to recover the full/root shelf.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Loading | Header and command bar plus centered progress | Search/control state remains visible; wait | Spines replace progress after repository load |
| Populated | Dense responsive spine rows with folders first | Open, search, sort, manage, create/import | Ink response and existing navigation/dialog feedback |
| Search | Query remains visible in the fixed search field; matching spines update | Edit/clear query, open/manage result | Clear restores the full current shelf |
| No results | Header plus existing no-matches state | Clear or edit query | Matching spines repopulate in place |
| Empty | Header plus existing actionable empty state | Create/import, return from archive/folder | Existing creation/import flow |
| Split view | Stacks command controls below search when required | Same actions with 44px targets | No horizontal page scrolling or clipped controls |

## Layout And Components

- Placement and hierarchy:
  - Remove `Scaffold.appBar`; place a custom header inside the safe area.
  - Header row: optional back, library mark, small `InkNest Notes` brand,
    location title and item summary, then Import PDF and New notebook icon actions.
  - Command row: always-visible search, a labelled current-sort control, New
    folder at root, and Archive/Library navigation.
  - Use a matching tonal furniture color for command-bar background and shelf rails.
  - Each row packs variable-width spines with no artificial gap; remaining
    last-row space stays empty instead of stretching books.
- Reused components:
  - Existing search controller, sort menus, action menu contents, dialogs, empty
    states, theme colors, and repository-derived state.
- New component or pattern, if justified:
  - `LibraryHeader`, responsive `LibraryCommandBar`, and `LibrarySpine`.
  - Deterministic muted spine palette, small height variation, one shared lean
    angle, and page-count-derived width provide identity without persisted
    settings.
- User-facing copy:
  - Root location title: `My Library` with brand label `InkNest Notes`.
  - Search placeholder remains `Search notebooks`.
  - Sort control displays its current value, such as `Recent` or `Title`.

## Book And Binder Spine Specification

- Notebook spine width follows a bounded logarithmic page-count curve: thin
  notebooks remain narrow, thicker notebooks grow visibly, and very large
  notebooks stop growing before they dominate the shelf.
- Title is rotated along the spine and truncated to one line when necessary.
- Page count is abbreviated at the lower end; the overflow action remains a
  separate 44px target.
- Spines touch their neighbors with no layout gap and use stable muted colors,
  small deterministic height differences, and one 3-degree leftward lean
  around the bottom-center shelf contact point. This gives every book the same
  visible resting direction against a support on its left side.
- Folder uses a binder-style color, folder mark, and `Folder` metadata while
  retaining the same tight row rhythm and tap behavior.
- The page thumbnail is intentionally not shown on the home shelf because its
  front-cover orientation conflicts with the outward-spine model.

## Input And Responsive Behavior

- Pencil and touch: Entire spine opens the item; overflow is a separate 44px
  action. No hidden swipe, drag, or long-press is required.
- Mouse/trackpad and keyboard: Material focus, hover, ripple, tooltips, and popup
  menu behavior remain available.
- iPad portrait/landscape: Header remains one hierarchy; command bar uses one row
  when it fits. Spine count grows with width while staying bounded inside centered
  library content.
- iPad split view: Search occupies its own row when needed and controls wrap below;
  spines reduce width slightly before the shelf becomes a single-column layout.
- Phone/Web: Phone uses the split-view header arrangement. A platform-specific
  navigation system remains outside this delivery.

## Accessibility

- Semantics and focus: Brand/title read before search and controls. Each spine is
  a named button (`Open notebook ...` or `Open folder ...`); each overflow menu
  retains its explicit action tooltip.
- Text scaling and contrast: Location and command labels must not clip at common
  text scales; spine foreground is high-contrast and does not rely on color alone.
- Non-gesture alternative: Standard buttons and menus expose every action.

## UI Acceptance Criteria

- [x] Header, command bar, shelves, and spines share one coherent visual language.
- [x] Search is immediately available and secondary controls stay grouped and
  reachable at iPad portrait, landscape, and split-view widths.
- [x] Books appear spine-out, bottom-aligned, and gapless; books lean subtly in
  the same 3-degree leftward support direction without being stretched to fill
  a row.
- [x] A notebook with more pages receives a wider spine within the documented
  bounds, and shelf wrapping uses the resulting actual widths.
- [x] Folder binders remain distinguishable without leaving the bookshelf model.
- [x] Whole-spine open targets and separate 44px overflow actions are accessible.
- [x] Search, loading, empty, archive, and folder states preserve clear feedback.
- [x] Closing the editor refreshes shelf metadata before the next interaction,
  so the page label, width, sort position, and next open use current notebook data.

## Verification

- Widget tests: Header location, always-visible search, current sort label, spine
  keys, action menus, and removal of front-cover thumbnails.
- Responsive/semantic tests: Multi-row dense shelves at 600px split width and
  named whole-spine open semantics.
- Manual device checks: iPad portrait/landscape density, rotated-title legibility,
  popup hit targets, and search keyboard behavior.

## Implementation Review

- Status: Complete
- Intentional deviations: None.
