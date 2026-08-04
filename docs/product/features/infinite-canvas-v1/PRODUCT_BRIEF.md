# Infinite Canvas V1 Product Brief

- Status: Delivered
- Size: Large
- Updated: 2026-08-04
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` — Editor Experience

## Problem

Paged notebooks are the right default for handwriting, PDF study, and export,
but they interrupt spatial work such as brainstorming, diagrams, and freeform
sketching. Users need a notebook type that can extend in every direction
without changing or weakening existing paged notebooks.

## Recommended Outcome

Add a backward-compatible notebook layout mode chosen at creation:

- **Paged notebook:** current behavior, data, editor, and export remain intact.
- **Infinite canvas:** one independent spatial document with its own storage and
  editor. It grows through world coordinates rather than allocating a giant
  bitmap or oversized fixed page.

V1 includes reliable handwriting, highlighter, stroke erasing, undo/redo,
Pencil/finger input modes, two-finger zoom and pan, blank/dotted/grid
backgrounds, and persisted content plus viewport restoration.

## Scope

### In scope

- Persist `paged` / `infiniteCanvas` on `Notebook`; missing values default to
  `paged` for every existing notebook.
- Choose the notebook type before creation and route to the matching editor.
- Store infinite content separately from paged `pages/*.json` data.
- Support negative and positive world coordinates without a giant backing
  surface.
- Reuse existing stroke, tool, smoothing, theme, and editor toolbar behavior
  where it is safe.
- Save after content/background changes and restore the last useful viewport.

### Non-goals for V1

- Mixing paged and infinite documents inside one notebook.
- PDF import/backgrounds, Pages, Outline, Bookmarks, audio, search, or PDF
  export inside infinite notebooks.
- Infinite-canvas text, images, shapes, lasso, collaboration, spatial chunking,
  or a minimap.
- Converting an existing paged notebook into an infinite canvas or back.

## Acceptance Criteria

- [x] New notebook presents Paged notebook and Infinite canvas choices; cancel
  creates nothing.
- [x] Existing notebook JSON without a layout mode opens as paged with no data
  migration or rewrite requirement.
- [x] Infinite canvas opens without page controls and supports pen,
  highlighter, eraser, undo, and redo.
- [x] Pencil/mouse can write; two-finger touch zooms/pans; Finger moves pans;
  Finger writes draws with the existing assist behavior.
- [x] Blank, Dotted, and Grid backgrounds repeat across the visible canvas.
- [x] Strokes may use negative or positive world coordinates and survive app
  restart along with background and viewport focus/scale.
- [x] Paged notebook creation and the complete paged editor regression suite
  remain unchanged after choosing Paged notebook.

## Risks

- Rendering every stroke is acceptable for V1 but needs spatial indexing and
  culling before very large production canvases.
- Viewport gesture ownership must never create a stroke during pinch/pan.
- Repository duplication/deletion must include the separate canvas document.

## Delivery

- UI/UX spec: `docs/product/features/infinite-canvas-v1/UI_UX_SPEC.md`
- Implementation status: Delivered; `flutter analyze` and all 138 tests pass.

## V2 Shared Editing Parity

- Status: First delivery slice delivered; broader shared capabilities remain
  planned.
- Product rule: paged and infinite notebooks share editing capabilities by
  default; only features whose meaning depends on pages are excluded.

### First delivery slice

- Reuse the existing Lasso behavior for selecting, moving, resizing,
  recoloring, and deleting ink in world coordinates.
- Reuse Insert for editable text boxes, notebook-relative images, and clean
  line, arrow, rectangle, and ellipse shapes.
- Persist text, images, and shapes in the independent canvas document and
  include them in fit-content bounds and content undo/redo.
- Preserve the single responsive top bar and expose Lasso and Insert there.

### Deferred shared capabilities

- Smart Ink, audio recording/playback, spatial text search, and canvas export
  follow after the shared content model is stable.

### Still page-specific

- Pages management, page templates, page bookmarks, page rotation, PDF import,
  PDF Outline, and page-range export.

### V2 acceptance criteria

- [x] Existing V1 canvas JSON without rich content remains readable.
- [x] Text boxes can be created, edited, moved, deleted, saved, and reopened.
- [x] Images can be inserted, moved, resized, deleted, saved, and reopened.
- [x] Shapes can be drawn with the same shape choices and properties as paged
  notebooks, including negative world coordinates.
- [x] Lasso selects and transforms canvas ink without conflicting with pan or
  pinch gestures.
- [x] Fit content and undo/redo include all delivered canvas content types.
- [x] The single top bar remains usable at supported iPad widths.

### V2 first-slice verification

- `flutter analyze` passes with no issues.
- All 141 tests pass, including rich-content JSON compatibility, file-backed
  image restoration, world-coordinate object editing, Lasso, undo/redo, and
  responsive toolbar coverage.
