# InkNest Notes Status

## Current

- Milestone: Post-MVP 2 - Library Organization
- Next task: Add notebook rename, delete, duplicate, and archive.
- Last completed: Improved stroke smoothing and partial erasing.

## Decisions

- Use `docs/ROADMAP.md` as the main checklist for project execution.
- Use this file as the short resume point for future sessions.
- Keep the first product direction iPadOS/iOS-first, handwriting-first, and paged-notebook based.
- Use project skill `.codex/skills/inknest-project` to recover context without rereading the whole repo.
- Keep the first app shell dependency-free; add state management and routing when notebook creation/navigation needs them.
- Use an in-memory notebook repository until local persistence begins.
- Keep first handwriting state in editor memory until local persistence begins.
- Use the first eraser as whole-stroke erasing by proximity; partial stroke splitting can come later.
- Store notebook metadata and page strokes as readable JSON under the app documents directory.
- Store page order on `Notebook.pageIds`; each page is saved as `pages/<page-id>.json`.
- Use `file_picker` for PDF selection and `pdfrx` for iOS/iPadOS PDF rendering.
- Use the `pdf` package for PDF export, `image` for rendered PDF background encoding, and `file_picker.saveFile` for the first save/share action.
- Exported annotated PDFs rasterize imported PDF backgrounds and overlay editable strokes as vector paths in the generated output.
- Pause sync and backup until the editor, PDF, and library workflows are more polished.
- Use `docs/POST_MVP_ROADMAP.md` for GoodNotes / Notability-style post-MVP planning.
- Use `docs/SUBSCRIPTION_PLAN.md` as the product reference for Free, InkNest Cloud, and future Pro monetization.
- Long-term product direction: iPad handwriting/PDF study, phone capture/review, and Web Yuque-like knowledge base.
- Use a custom two-finger zoom/pan viewport instead of `InteractiveViewer` so single-pointer drawing remains reliable.
- Keep finger drawing available by default; use an explicit Finger pan mode to make touch drag the page while stylus/mouse input writes.
- Keep the first page thumbnail strip lightweight: show page shape, selection state, handwriting preview, and a PDF marker before adding full PDF thumbnail caching.
- Store page operations in the repository layer: duplicate inserts after the source page, delete keeps at least one page, and reorder starts with thumbnail menu move-left/move-right actions.
- Use shared stroke geometry helpers for smoothed screen drawing, thumbnail drawing, PDF export paths, and partial eraser stroke splitting.

## Verification

- `dart format lib test` passed.
- `flutter test` passed.
- `flutter analyze` passed.
- `git diff --check` passed after the post-MVP documentation update.
- `dart format lib test` passed after editor zoom/pan.
- `flutter test` passed after editor zoom/pan.
- `flutter analyze` passed after editor zoom/pan.
- `dart format lib test` passed after Finger pan mode.
- `flutter test` passed after Finger pan mode.
- `flutter analyze` passed after Finger pan mode.
- `dart format lib test` passed after page thumbnails.
- `flutter test` passed after page thumbnails.
- `flutter analyze` passed after page thumbnails.
- `dart format lib test` passed after page duplicate/delete/reorder.
- `flutter test` passed after page duplicate/delete/reorder.
- `flutter analyze` passed after page duplicate/delete/reorder.
- `dart format lib test` passed after stroke smoothing and partial erasing.
- `flutter test` passed after stroke smoothing and partial erasing.
- `flutter analyze` passed after stroke smoothing and partial erasing.

## Notes

- `lib/main.dart` now starts `InkNestApp`.
- App/theme code lives under `lib/app`.
- Library, notebook, and editor feature folders exist under `lib/features`.
- Library can create `Notebook 1` and navigate to an editor placeholder.
- Editor has a fixed white page canvas, captures pointer strokes, renders with `CustomPainter`, and supports undo/redo.
- Editor toolbar supports pen, highlighter, eraser, color choices, and width choices.
- File storage layout is documented in `docs/STORAGE.md`.
- Editor can add pages, switch pages, and persist each page independently.
- Library can import a PDF, copy it into notebook assets, create one note page per PDF page, and render the PDF page behind editable strokes.
- Editor can export the current notebook as a PDF, including blank pages, imported PDF page backgrounds, and handwriting strokes.
- Editor page viewport supports zoom controls and two-finger pinch/pan without saving accidental strokes.
- Editor toolbar includes Finger pan mode; when enabled, touch drags the page and stylus input still writes.
- Editor bottom navigator now shows page thumbnails with selection state, page numbers, handwriting previews, and PDF page markers.
- Editor page thumbnails include actions to duplicate, delete with confirmation, and move pages left or right.
- Editor strokes render with smoothed paths on canvas, thumbnails, and exported PDFs; the eraser can split strokes instead of only deleting whole strokes.
- Post-MVP feature gaps and optimization areas are documented in `docs/POST_MVP_ROADMAP.md`.
- Subscription packaging, platform behavior, and local/cloud merge rules are documented in `docs/SUBSCRIPTION_PLAN.md`.
- Web knowledge-base, mobile companion, collaboration, and AI directions are captured as later post-MVP milestones.
