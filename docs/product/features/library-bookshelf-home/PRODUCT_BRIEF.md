# Library Bookshelf Home Product Brief

- Status: Accepted
- Size: Medium
- Updated: 2026-07-18
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` - Library And Organization

## Problem

The dedicated Recent strip has been removed, but the current screen still mixes
a conventional Material app bar with front-facing notebook cards on shelf
rails. The header and content therefore speak different visual languages, and
the books do not behave like a real bookshelf where outward-facing spines sit
closely together.

## Recommended Outcome

Use one coherent library-room composition. Replace the generic app bar with an
integrated library header and a visible search/control bar. Present notebooks as
dense outward-facing spines resting on shared shelf rows, while folders appear
as thicker binder spines. Keep Recent as the default and selectable sort order
so recently edited work remains easiest to reach without a duplicate surface.

## Scope

- In scope:
  - Remove the Recent notebooks strip and its separate thumbnail entry points.
  - Replace the generic app bar with an integrated title and command area.
  - Keep search visible and group sort, folder, and archive navigation as
    secondary library controls.
  - Replace front-facing cards with tightly spaced responsive book/binder spines.
  - Use deterministic spine color and height with one shared, clearly visible
    leftward lean angle; derive bounded spine width from notebook page count
    without storing cover preferences.
  - Refresh repository-derived notebook metadata whenever the editor closes so
    page count, width, ordering, and the next editor session use current data.
  - Preserve search, all sort modes, folder navigation, archive navigation,
    notebook actions, empty states, and vertical scrolling behavior.
- Non-goals:
  - Custom spine editing, user-selectable shelf themes, or persisted cover data.
  - Drag-and-drop reordering, favorites, tags, or nested folders.
  - Repository, persistence, or notebook data-model changes.
  - Phone- or Web-specific navigation redesign.

## User Flow

1. The user opens InkNest and sees a single library header above rows of spines.
2. The user searches directly or uses the compact secondary controls to sort,
   enter folders, or view the archive.
3. The user taps a spine to open it or its accessible overflow control for
   management actions; clearing search returns to the same shelf context.

## Acceptance Criteria

- [x] Recent notebooks is no longer rendered as a separate home-screen section.
- [x] The old AppBar is replaced by one visually integrated library header and
  command bar.
- [x] Existing notebooks and folders render as tightly spaced outward-facing
  spines on stable responsive shelf rows.
- [x] Adjacent spines have no artificial gap, use the same clearly visible
  leftward angle from their shelf base, and become wider within safe bounds as
  page count grows.
- [x] Spine titles, compact page counts, and action menus remain readable and
  usable without front-facing page thumbnails.
- [x] Search, title/date/recent sorting, folders, archive, import, and creation
  flows retain their existing behavior.
- [x] Empty and no-search-result states remain clear and actionable.
- [x] Returning from an edited notebook immediately refreshes its shelf page
  count, page-derived width, and subsequent editor input data.
- [x] No notebook data or persistence migration is introduced.

## Alternatives And Tradeoffs

- Option: Keep front-facing preview cards on shelf rails.
- Why not now: Front covers require large gaps and read as a gallery, not a row
  of books stored on a shelf.
- Option: Use a fully realistic wooden cabinet and textured books.
- Why not now: Heavy skeuomorphism would compete with titles and controls; tonal
  furniture surfaces plus colored spines preserve clarity and theme flexibility.

## Dependencies And Risks

- Product or technical dependency: Existing repository results remain the
  source of truth; visible spine variation must be deterministic from existing
  IDs and introduce no stored cover state.
- Data, privacy, performance, or migration risk: No new stored data. The custom
  row layout must remain lazy and bounded so large libraries still scroll
  efficiently.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/library-bookshelf-home/UI_UX_SPEC.md`
- Implementation status: Complete
- Verification: Zero-gap, variable-width, lean, split-view, full Flutter,
  analyzer, formatting, and diff checks passed.
