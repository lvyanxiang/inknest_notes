# InkNest Product Decisions

Record accepted, durable product decisions here. Detailed requirements belong
in `docs/product/features/<feature-slug>/PRODUCT_BRIEF.md`.

| Date | Feature | Accepted decision | Status | Artifact |
|---|---|---|---|---|
| 2026-08-05 | InkNest Cloud authentication | Use email/password for the first account flow without mandatory email verification during initial development; issue short-lived JWT access tokens and rotate opaque refresh tokens whose hashes and device ownership are stored server-side. | Delivered | `docs/product/features/inknest-cloud-backend/PRODUCT_BRIEF.md` |
| 2026-08-05 | InkNest Cloud backend | Add a custom Python service as `server/` in the existing repository; use PostgreSQL for authoritative sync metadata and MinIO for binary objects, keep the app local-first, default first sign-in to merge, and preserve conflicts instead of silently overwriting local notes. | Planned | `docs/product/features/inknest-cloud-backend/PRODUCT_BRIEF.md` |
| 2026-08-04 | Infinite canvas shared editing | Treat editing capability parity as the default: reuse Lasso, text, images, and shapes first while excluding only page-structured features such as PDF pages, Outline, and page bookmarks. | Delivered | `docs/product/features/infinite-canvas-v1/PRODUCT_BRIEF.md` |
| 2026-08-03 | Infinite canvas V1 | Add an explicit notebook layout type; keep paged notebooks unchanged and store a separate world-coordinate infinite canvas with focused V1 writing tools and persisted viewport state. | Delivered | `docs/product/features/infinite-canvas-v1/PRODUCT_BRIEF.md` |
| 2026-08-03 | Editor workspace V2 | Separate document actions from editing mode; give Pages, Outline, and Bookmarks focused entry points; choose paper style before blank-page insertion; restore one-tap Pen/Highlighter switching; and adapt direct actions to width. | Delivered | `docs/product/features/editor-workspace-v2/PRODUCT_BRIEF.md` |
| 2026-07-27 | Editor workspace interaction polish | Prefer a clear writing surface over permanent canvas chrome: collapse zoom controls, remove the floating page chip, use anchored tool properties on iPad widths, and expose Fit Width / Fit Page from More → View. | Delivered | `docs/product/features/editor-workspace-polish/PRODUCT_BRIEF.md` |
| 2026-07-18 | Library bookshelf home | Use one integrated library header and dense outward-facing spine shelf; keep normal notebook opening as one action after brief pull-forward feedback, with optional inspection for truncated titles. | Delivered | `docs/product/features/library-bookshelf-home/PRODUCT_BRIEF.md` |
