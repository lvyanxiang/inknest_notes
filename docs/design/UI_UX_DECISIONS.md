# InkNest UI/UX Decisions

Record accepted, reusable interaction or visual patterns here. Feature-specific
details belong in `docs/product/features/<feature-slug>/UI_UX_SPEC.md`.

| Date | Pattern | Accepted decision | Status | Artifact |
|---|---|---|---|---|
| 2026-08-06 | Conflict recovery | Surface background sync conflicts through persistent sync status instead of interrupting writing; show device/time as metadata and offer Keep Original, Use Conflict Version, and emphasized Keep Both in an accessible detail sheet. | Planned | `docs/product/features/inknest-cloud-backend/UI_UX_SPEC.md` |
| 2026-08-04 | Cross-layout editor tools | Keep shared tools and labels consistent between paged and infinite notebooks; adapt coordinates and selection behavior instead of hiding capabilities that do not depend on pages. | Delivered | `docs/product/features/infinite-canvas-v1/UI_UX_SPEC.md` |
| 2026-08-03 | Notebook layout modes | Choose Paged notebook or Infinite canvas before creation; use a focused world-coordinate canvas editor without page-only controls and preserve exclusive Pencil/finger gesture ownership. | Delivered | `docs/product/features/infinite-canvas-v1/UI_UX_SPEC.md` |
| 2026-08-03 | Editor command hierarchy | Use a compact pager, separate Pages / Outline / Bookmarks panels, and paper-style-first blank-page insertion; keep page actions out of More and adapt Record/Export shortcuts to width. | Delivered | `docs/product/features/editor-workspace-v2/UI_UX_SPEC.md` |
| 2026-07-27 | Collapsible editor zoom chrome | Keep a quiet Fit-Width-relative zoom chip that expands on demand, show a transient center zoom badge while zooming, and expose Fit Width / Fit Page from More → View as well as the zoom menu. | Delivered | `docs/product/features/editor-workspace-polish/UI_UX_SPEC.md` |
| 2026-07-18 | Unified spine bookshelf library | Keep gapless page-weighted spines at a shared 3-degree left lean; tap briefly pulls and scales a notebook before opening, while long press, hover, or focus holds inspection and tips only truncated titles. | Delivered | `docs/product/features/library-bookshelf-home/UI_UX_SPEC.md` |
