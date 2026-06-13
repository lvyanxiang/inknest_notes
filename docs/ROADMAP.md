# InkNest Notes Roadmap

InkNest Notes is a Flutter note-taking app inspired by GoodNotes and Notability.
The first milestone is not to clone every feature, but to build a reliable,
pleasant handwriting core that can grow into notebooks, PDF annotation, export,
and sync.

## Product Direction

- Primary target: iPadOS / iOS first.
- First experience: open the app into a notebook library, then write quickly.
- Core principle: handwriting latency, persistence, and editing reliability come before advanced features.
- Initial document model: paged notebooks rather than infinite canvas.

## Milestone 0: Project Foundation

Goal: replace the Flutter counter template with a maintainable app skeleton.

Acceptance criteria:

- App has a clear name, theme, and entry structure.
- `lib/` is organized by app, features, models, storage, and shared utilities.
- Basic widget test reflects the new app shell.

Tasks:

- [x] Replace counter demo with `InkNest Notes` app shell.
- [x] Create app-level structure under `lib/app`.
- [x] Create feature folders for library, notebook, and editor.
- [x] Add an initial visual theme suitable for a note-taking tool.
- [x] Update the default widget test.

## Milestone 1: Notebook Library MVP

Goal: let users create and open notebooks.

Acceptance criteria:

- App starts at a notebook library screen.
- Empty state is useful and polished.
- User can create a notebook.
- User can open a notebook editor screen.

Tasks:

- [x] Build notebook library screen.
- [x] Add empty state and create-notebook action.
- [x] Define `Notebook` model.
- [x] Add in-memory notebook repository.
- [x] Navigate from library to editor.

## Milestone 2: Single-Page Handwriting Core

Goal: support smooth handwriting on one fixed-size page.

Acceptance criteria:

- User can draw strokes on a white page.
- Strokes are rendered with `CustomPainter`.
- Each completed stroke is stored as structured data.
- Undo and redo work per stroke.

Tasks:

- [x] Define `NotePage`, `Stroke`, `StrokePoint`, and `Tool` models.
- [x] Build editor screen with a fixed page canvas.
- [x] Capture pointer events for drawing.
- [x] Render strokes with `CustomPainter`.
- [x] Add pen color and width settings.
- [x] Add undo and redo.

## Milestone 3: Editor Tools

Goal: make the editor feel like a real writing surface.

Acceptance criteria:

- User can switch between pen, highlighter, and eraser.
- Tool controls are compact and reachable.
- Canvas interactions do not conflict with toolbar interactions.

Tasks:

- [x] Add editor toolbar.
- [x] Add pen tool.
- [x] Add highlighter tool.
- [x] Add eraser tool.
- [x] Add color selector.
- [x] Add width selector.
- [x] Improve touch target sizing for tablet use.

## Milestone 4: Local Persistence

Goal: keep notebooks and handwriting after closing the app.

Acceptance criteria:

- Created notebooks persist locally.
- Page strokes persist locally.
- Reopening a notebook restores its page content.
- Storage format is easy to inspect and migrate.

Tasks:

- [x] Define file-based storage layout.
- [x] Implement JSON serialization for notebook data.
- [x] Implement local notebook repository.
- [x] Save strokes after editing.
- [x] Load saved notebooks on app start.
- [x] Add basic repository tests.

## Milestone 5: Multi-Page Notebooks

Goal: support a notebook with more than one page.

Acceptance criteria:

- User can add pages.
- User can switch between pages.
- Each page maintains separate strokes.
- Page order is stable after reopening the app.

Tasks:

- [ ] Add page list or page navigator.
- [ ] Add new-page action.
- [ ] Store multiple pages per notebook.
- [ ] Navigate between pages.
- [ ] Persist page order and page content.

## Milestone 6: PDF Import and Annotation

Goal: import PDFs and write on top of them.

Acceptance criteria:

- User can import a PDF file.
- Each PDF page appears as a notebook page background.
- User can write over PDF pages.
- Notes remain editable after reopening.

Tasks:

- [ ] Evaluate Flutter PDF rendering packages for iOS/iPadOS.
- [ ] Add file picker.
- [ ] Copy imported PDFs into app storage.
- [ ] Render PDF pages as page backgrounds.
- [ ] Bind PDF page background to `NotePage`.
- [ ] Test annotation persistence.

## Milestone 7: Export

Goal: let users take their notes out of the app.

Acceptance criteria:

- User can export a notebook as PDF.
- Export includes page backgrounds and handwriting.
- Exported file opens correctly in common PDF viewers.

Tasks:

- [ ] Design export pipeline.
- [ ] Render note pages with strokes into export output.
- [ ] Export blank-page notebooks.
- [ ] Export annotated PDFs.
- [ ] Add share/save action.

## Milestone 8: Sync and Backup

Goal: protect user data across devices.

Acceptance criteria:

- User can back up notebooks.
- Sync does not corrupt local edits.
- Conflict behavior is explicit.

Tasks:

- [ ] Choose sync target: iCloud, WebDAV, or custom backend.
- [ ] Define sync metadata.
- [ ] Add backup/export archive format.
- [ ] Implement first sync prototype.
- [ ] Handle conflicts safely.

## Technical Notes

Recommended early dependencies:

- `flutter_riverpod` for state management.
- `go_router` for navigation.
- `path_provider` for app document storage.
- `uuid` for stable IDs.
- `freezed` and `json_serializable` once the data model stabilizes.
- `file_picker` when PDF import begins.

Initial storage layout idea:

```text
documents/
  notebooks/
    notebook-id/
      notebook.json
      pages/
        page-id.json
      assets/
        imported.pdf
```

## Current Focus

Start with Milestone 0, then move through the roadmap in order. When a task is
completed, mark it with `[x]` and keep notes in this file if the implementation
choice affects later milestones.
