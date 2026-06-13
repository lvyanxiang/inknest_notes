# InkNest Notes Status

## Current

- Milestone: 3 - Editor Tools
- Next task: Add editor toolbar.
- Last completed: Milestone 2 single-page handwriting core.

## Decisions

- Use `docs/ROADMAP.md` as the main checklist for project execution.
- Use this file as the short resume point for future sessions.
- Keep the first product direction iPadOS/iOS-first, handwriting-first, and paged-notebook based.
- Use project skill `.codex/skills/inknest-project` to recover context without rereading the whole repo.
- Keep the first app shell dependency-free; add state management and routing when notebook creation/navigation needs them.
- Use an in-memory notebook repository until local persistence begins.
- Keep first handwriting state in editor memory until local persistence begins.

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
