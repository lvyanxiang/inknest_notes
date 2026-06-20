# InkNest Notes Status

## Current

- Milestone: Post-MVP 3 - PDF Study Workflow
- Next task: Add page-range export.
- Last completed: Added PDF thumbnails, outlines, and bookmarks.

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
- Keep archived notebooks out of the default library list; show them through an explicit archived view where they can be restored or deleted.
- Store folders as first-class repository metadata; keep folders one level deep for now, and use `Notebook.folderId` to move notebooks between the root library and a folder.
- Keep library search and sort as UI-level derived state over repository results for now.
- Render first-pass notebook thumbnails from the first page's saved strokes plus lightweight PDF/page markers before adding cached PDF bitmap thumbnails.
- Store blank-page insertion in the repository layer; inserted pages inherit the nearest page size but start without PDF background or strokes.
- Store imported PDF outlines on `Notebook.pdfOutlines`, keyed to notebook page IDs so page insertion and reordering do not break outline navigation.
- Store user page bookmarks on `Notebook.bookmarkedPageIds` and persist them through the repository layer.
- Let PDF import continue when outline loading fails; the Outline tab simply starts empty.

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
- `dart format lib test` passed after notebook library actions.
- `flutter test` passed after notebook library actions.
- `flutter analyze` passed after notebook library actions.
- `dart format lib test` passed after folders.
- `flutter test` passed after folders.
- `flutter analyze` passed after folders.
- `dart format lib test` passed after library search, sort, recent notebooks, and thumbnails.
- `flutter test` passed after library search, sort, recent notebooks, and thumbnails.
- `flutter analyze` passed after library search, sort, recent notebooks, and thumbnails.
- `git diff --check` passed after library search, sort, recent notebooks, and thumbnails.
- `dart format lib test` passed after inserting blank pages.
- `flutter test` passed after inserting blank pages.
- `flutter analyze` passed after inserting blank pages.
- `git diff --check` passed after inserting blank pages.
- `dart format lib test` passed after PDF thumbnails, outlines, and bookmarks.
- `flutter test` passed after PDF thumbnails, outlines, and bookmarks.
- `flutter analyze` passed after PDF thumbnails, outlines, and bookmarks.
- `git diff --check` passed after PDF thumbnails, outlines, and bookmarks.

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
- Library notebook cards include rename, duplicate, archive/restore, and delete actions backed by repository persistence.
- Library supports creating root-level folders, moving notebooks into folders, entering folders, and deleting folders while moving contained notebooks back to the root library.
- Library supports searching notebooks and folders, sorting notebooks, opening recent notebooks, and showing first-page notebook thumbnails with handwriting/PDF/archive markers.
- Editor page thumbnails can insert blank pages before or after any page, including between imported PDF pages.
- Editor page thumbnails render PDF page backgrounds, and the editor has an Outline/Bookmarks panel plus per-page bookmark toggling.
- Post-MVP feature gaps and optimization areas are documented in `docs/POST_MVP_ROADMAP.md`.
- Subscription packaging, platform behavior, and local/cloud merge rules are documented in `docs/SUBSCRIPTION_PLAN.md`.
- Web knowledge-base, mobile companion, collaboration, and AI directions are captured as later post-MVP milestones.
