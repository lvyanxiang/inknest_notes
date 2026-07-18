# Library Bookshelf Home Product Brief

- Status: Accepted
- Size: Medium
- Updated: 2026-07-18
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` - Library And Organization

## Problem

The root library currently presents the same recently updated notebooks twice:
once in a dedicated Recent notebooks strip and again in the main grid. This
duplicates navigation, consumes the most valuable area of the home screen, and
makes the library feel like a generic file grid rather than a notebook product.

## Recommended Outcome

Use one responsive bookshelf as the primary library. Notebooks appear as
book-like covers resting on shared shelf rows, while folders remain visibly
distinct collection items. Remove the dedicated Recent notebooks strip, but
keep Recent as the default and selectable sort order so recently edited work is
still easiest to reach without a duplicate surface.

## Scope

- In scope:
  - Remove the Recent notebooks strip and its separate thumbnail entry points.
  - Replace the flat library grid with responsive bookshelf rows.
  - Refresh notebook and folder cards while preserving preview thumbnails.
  - Preserve search, all sort modes, folder navigation, archive navigation,
    notebook actions, empty states, and pull-free scrolling behavior.
- Non-goals:
  - Custom notebook cover editing or user-selectable shelf themes.
  - Drag-and-drop reordering, favorites, tags, or nested folders.
  - Repository, persistence, or notebook data-model changes.
  - Phone- or Web-specific navigation redesign.

## User Flow

1. The user opens InkNest and sees folders and notebooks on a single bookshelf.
2. The user taps a book to open it, a folder to enter it, or an accessible
   overflow menu for management actions.
3. The user can search or change sorting; clearing search returns to the same
   bookshelf. Recent sorting remains available without a second recent section.

## Acceptance Criteria

- [x] Recent notebooks is no longer rendered as a separate home-screen section.
- [x] Existing notebooks and folders render in stable responsive shelf rows.
- [x] Notebook thumbnails, titles, page counts, and action menus remain visible
  and usable.
- [x] Search, title/date/recent sorting, folders, archive, import, and creation
  flows retain their existing behavior.
- [x] Empty and no-search-result states remain clear and actionable.
- [x] No notebook data or persistence migration is introduced.

## Alternatives And Tradeoffs

- Option: Keep the existing grid and only restyle individual cards.
- Why not now: It removes little duplication and does not create the stronger
  notebook-library identity requested for the home screen.
- Option: Add a fully realistic wooden bookshelf.
- Why not now: Heavy skeuomorphism would reduce visual flexibility and compete
  with notebook previews; a restrained shared shelf gives the metaphor without
  sacrificing Material behavior or readability.

## Dependencies And Risks

- Product or technical dependency: Existing repository results and notebook
  thumbnail renderer remain the source of truth.
- Data, privacy, performance, or migration risk: No new stored data. The custom
  row layout must remain lazy and bounded so large libraries still scroll
  efficiently.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/library-bookshelf-home/UI_UX_SPEC.md`
- Implementation status: Complete
- Verification: Library and split-view widget tests passed; full Flutter tests,
  analyzer, formatting, and diff checks passed.
