# InkNest Notes Status

## Current

- Milestone: 7 - Export
- Next task: Design export pipeline.
- Last completed: Milestone 6 PDF import and annotation.

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

## Verification

- `dart format lib test` passed.
- `flutter test` passed.
- `flutter analyze` passed.

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
