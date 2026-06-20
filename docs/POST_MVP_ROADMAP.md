# InkNest Notes Post-MVP Roadmap

This document starts after the current MVP baseline:

- Notebook library.
- Local notebook persistence.
- Multi-page handwriting notebooks.
- Pen, highlighter, eraser, color, and width controls.
- PDF import and annotation.
- PDF export.

Milestone 8 sync and backup is intentionally paused. Data protection remains
important, but the next product work should first make the core writing,
reading, organizing, and PDF workflows feel closer to GoodNotes and Notability.

## Product Goal

InkNest should become a polished iPad-first note-taking app for handwriting,
PDF study, document organization, and reliable export. The next phase should
not chase every competitor feature at once; it should deepen the features users
touch every session.

Long term, InkNest should grow beyond a GoodNotes / Notability-style notebook
into a cross-device knowledge product:

- iPad: deep handwriting, PDF study, classroom notes, meeting notes, and offline
  creation.
- Phone: quick capture, review, search, scanning, audio, and lightweight notes.
- Web: a Yuque-like knowledge base for organizing, editing, searching,
  sharing, and connecting notes into durable knowledge.

The product promise is: write ideas down naturally, then turn them into
structured knowledge.

For users without a stylus, InkNest should also offer a Smart Ink path:
rough finger handwriting can be recognized as text, confirmed by the user, and
re-rendered as neat handwriting-style editable text.
The detailed plan lives in `docs/SMART_INK_PLAN.md`.

## New Features To Add

### Editor Experience

- Zoom and pan with two-finger gestures.
- Apple Pencil-focused input mode with finger pan and Pencil draw behavior.
- Finger Writing Assist for smoothing rough finger handwriting before any
  recognition step.
- Page thumbnail strip or sidebar for faster page navigation.
- Page templates: blank, ruled, dotted, grid, Cornell, planner.
- Page actions: duplicate, delete, reorder, rotate, and insert before/after.
- Lasso selection for moving, resizing, recoloring, and deleting strokes.
- Text boxes for typed notes.
- Handwriting-style text rendering for typed or recognized text.
- Smart Ink beautify flow: select rough handwriting, recognize it as text,
  confirm the result, then replace or insert a neat handwriting-style version
  (`docs/SMART_INK_PLAN.md`).
- Image insertion from Photos or Files.
- Shape tool for lines, arrows, rectangles, circles, and auto-shape cleanup.
- Favorites toolbar for common pens, highlighters, and colors.

### PDF And Study Workflow

- Import multiple PDFs into an existing notebook.
- Insert blank pages before, after, or between PDF pages.
- PDF page thumbnails, outlines, and bookmarks.
- PDF search when the source PDF has selectable text.
- Export options: non-contiguous selected pages and flattened PDF refinements.
- Preserve original PDF page size where possible instead of forcing every PDF
  page into the same page dimensions.

### Library And Organization

- Rename, delete, duplicate, and archive notebooks.
- Folder support.
- Notebook covers and preview thumbnails.
- Sort by recent, title, created date, and updated date.
- Search notebooks by title.
- Recent notebooks section.
- Trash/recovery for deleted notebooks.

### Notability-Like Capabilities

- Audio recording attached to a notebook.
- Playback timeline linked to written strokes.
- Simple presentation mode.
- Split view or multi-window support for iPad workflows.

### Advanced Capabilities

- Handwriting recognition and full-text search.
- Smart Ink recognition for converting selected handwriting into editable text
  before re-rendering it with handwriting-style fonts.
- OCR for imported images and scanned PDFs.
- Shared notebooks or collaboration.
- Cross-device sync and backup, revisiting the paused Milestone 8.

### Mobile Companion

- Fast note capture on phone.
- Read and search notebooks from the phone.
- Capture photos or scans into a notebook.
- Record audio notes.
- Add lightweight typed notes.
- Review recent and favorite notebooks.

### Web Knowledge Base

- Space and knowledge-base structure similar to Yuque-style products.
- Folder tree or document hierarchy.
- Markdown or rich-text documents.
- Embed handwritten pages, notebook pages, PDFs, and images inside documents.
- Link notebooks and documents together.
- Tags, backlinks, references, and favorites.
- Full-text search across typed notes, OCR text, PDF text, and recognized
  handwriting.
- Share links for documents or notebooks.
- Team spaces and collaborative editing later.
- AI summaries, question answering, and knowledge-base retrieval later.

## Existing Features To Optimize And Extend

### Handwriting Canvas

- Improve stroke smoothing and reduce jitter.
- Add pressure-sensitive width for Pencil input.
- Support partial erasing instead of whole-stroke erasing only.
- Improve highlighter blend behavior on PDF backgrounds.
- Keep latency low as page stroke count grows.
- Add canvas virtualization or repaint boundaries for large notebooks.

### Persistence

- Add autosave debouncing and an explicit save queue.
- Avoid rewriting page files more often than necessary.
- Add storage migrations for future model changes.
- Add crash-safe writes using temporary files and atomic replacement.
- Generate thumbnails during save or in a background queue.

### PDF Rendering

- Cache rendered PDF page backgrounds.
- Avoid reloading PDF documents unnecessarily.
- Improve behavior for very large PDFs.
- Support encrypted or password-protected PDFs later.
- Improve export quality and file size tradeoffs.

### Export

- Add export progress and cancellation.
- Allow non-contiguous selected-page export.
- Add share-sheet flow in addition to save-to-file.
- Preserve page dimensions and PDF metadata where possible.
- Explore overlaying annotations on original PDF pages instead of rasterizing
  backgrounds for export.

### Editor UI

- Make tool controls more compact for iPad landscape use.
- Add keyboard shortcuts for undo, redo, tool switching, and export.
- Add undo/redo history per page with clearer state.
- Improve page navigator density and thumbnails.
- Add accessibility labels for all important controls.

### Testing And Release Quality

- Add golden tests for editor UI states.
- Add storage migration tests.
- Add export snapshot tests for generated PDFs.
- Add large notebook performance tests.
- Add manual QA checklist for iPad real-device builds.
- Track known iOS / Flutter engine issues in a release checklist.

## Suggested Next Milestones

### Post-MVP 1: Editor Usability

Goal: make writing and navigating a notebook feel natural on iPad.

- [x] Add zoom and pan.
- [x] Add Pencil draw plus finger pan mode.
- [x] Add page thumbnails.
- [x] Add page duplicate, delete, and reorder.
- [x] Improve stroke smoothing and partial erasing.

### Post-MVP 2: Library Organization

Goal: make notebooks manageable as the user creates more documents.

- [x] Rename, delete, duplicate, and archive notebooks.
- [x] Add folders.
- [x] Add sorting, search, recent notebooks, and notebook thumbnails.

### Post-MVP 3: PDF Study Workflow

Goal: make PDF annotation feel like a real study workflow.

- [x] Insert blank pages into PDFs.
- [x] Add PDF thumbnails, outlines, and bookmarks.
- [x] Add page-range export.
- [x] Improve PDF background caching and export quality.

### Post-MVP 4: Rich Notes

Goal: support mixed handwritten and typed notes.

- [ ] Add text boxes.
- Add handwriting-style text rendering.
- Add Smart Ink beautify: lasso rough handwriting, recognize text, confirm, and
  replace with neat handwriting-style editable text. See
  `docs/SMART_INK_PLAN.md`.
- Add image insertion.
- Add shape tool.
- Add favorites toolbar.

### Post-MVP 5: Audio And Search

Goal: add Notability-style study features.

- Add audio recording.
- Link playback timeline with strokes.
- Add PDF text search.
- Explore handwriting recognition and OCR for search and Smart Ink.

### Post-MVP 6: Sync And Backup

Goal: resume the paused data protection milestone once local editing and
document workflows are stable.

- Choose sync target.
- Define sync metadata.
- Add notebook archive format.
- Implement backup and restore.
- Add conflict detection and explicit recovery behavior.

### Post-MVP 7: Mobile Companion

Goal: make phone apps useful for capture, review, and lightweight notes without
trying to match the full iPad writing surface.

- Add account-backed notebook list.
- Add read-only notebook and PDF viewing.
- Add quick typed notes.
- Add camera scan import.
- Add audio capture.
- Add global search.

### Post-MVP 8: Web Knowledge Base

Goal: turn synced notes into an organized knowledge base on the Web.

- Add Web workspace and document hierarchy.
- Add Markdown or rich-text document editing.
- Embed notebook pages and PDFs in Web documents.
- Add tags, backlinks, and favorites.
- Add search across documents and synced notebook content.
- Add sharing links.

### Post-MVP 9: Collaboration And AI

Goal: make the knowledge base useful for teams, study, and long-term retrieval.

- Add team spaces.
- Add comments and collaborative editing.
- Add AI summaries.
- Add AI question answering over selected notebooks or spaces.
- Add flashcards or quiz generation.
