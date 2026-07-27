# Editor Workspace and Stable Page Viewport Product Brief

- Status: Implemented for canonical v1 pages; legacy archive/conversion follow-up remains
- Size: Large
- Updated: 2026-07-27
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` — Editor UI

## Problem

InkNest's iPad editor exposes a broad feature set, but its current structure
makes frequent writing actions hard to understand and gives rare commands the
same visual weight as primary tools.

- The document bar presents ten icon-only commands at once.
- The 72px editor toolbar mixes seven tools, a second shape selector, two touch
  modes, four colors, three widths, and image insertion in one horizontally
  scrolling row.
- Favorite presets duplicate the color and width controls in a separate canvas
  overlay.
- Zoom controls and a permanent 118px page strip consume or cover writing
  space, especially in landscape.
- Tool-specific properties remain visible when they do not apply, and Pen,
  Highlighter, and Eraser share one color and width state.

There is also an editing-reliability problem behind the responsive layout. A
`NotePage` has a fixed document size, but the current editor lays the page
surface out at a screen-fitted size and stores local pointer positions as if
they were document coordinates. Device rotation, Split View, a software
keyboard, or an audio bar can therefore change the relationship between saved
content and the paper. This can move, clip, or misalign strokes, text, images,
shapes, templates, selections, and export output.

The target user is an iPad note taker who needs to start writing immediately,
switch common tools without hunting, and trust that the same paper location
remains under the Pencil when the window changes.

## Recommended Outcome

Adopt a writing-first editor workspace with four coordinated changes:

1. **Stable document space.** Lay out every page at its persisted
   `page.width × page.height`, keep all editable content in that coordinate
   system, and apply one shared viewport transform for page rotation, zoom, and
   pan.
2. **Layered commands.** Use a compact document header for navigation and
   document-level actions, plus a contextual editing dock for the active tool.
   Move lower-frequency actions into clearly labelled grouped menus.
3. **Contextual tool properties.** Keep Pen, Highlighter, Eraser, and Lasso
   immediately available; group Text, Image, and Shape under Insert; expose
   Smart Ink after an ink selection. Show only the active tool's relevant
   properties.
4. **On-demand page navigation.** Replace the permanent bottom thumbnail strip
   with a collapsible left navigator on wide windows and an overlay navigator
   on portrait or narrow windows.

The initial writing view uses **Fit Width**, not automatic whole-page fit.
**Fit Page** remains an explicit overview command. Fit modes are provisional:
the first pan, zoom, or content gesture locks the view into Custom mode at its
current effective scale. Once writing has started, resize or device rotation
therefore preserves the writing scale and the document point at the center of
the usable canvas whenever bounds allow.

This direction matches InkNest's paged-notebook model and gives writing
reliability priority over a visual-only reskin.

## Scope

- In scope:
  - iPad full-screen portrait and landscape layouts.
  - Narrow iPad Split View and resizable-window behavior.
  - A reorganized document header, contextual tool dock, grouped overflow
    menus, and unambiguous selected states.
  - Integrated complete presets that carry tool type, color, and width instead
    of separate always-visible color and width rows.
  - Independent remembered settings for Pen, Highlighter, Eraser, and Shape.
  - Four fixed first-delivery presets: Black Pen 3pt, Teal Pen 5pt, Red Pen
    5pt, and Yellow Highlighter 12pt. Manual property changes create a Custom
    configuration without overwriting a preset.
  - A responsive Pages / Outline / Bookmarks navigator using the current page
    thumbnails and actions.
  - A fixed document-coordinate page surface and a shared transform for every
    page layer and hit test.
  - Fit Width, Fit Page, custom zoom, page-aware viewport memory for the current
    editing session, and focus preservation across viewport changes.
  - Clear busy, disabled, permission, cancellation, and save-failure feedback
    for existing editor actions.
  - Accessibility labels, focus order, keyboard alternatives for core
    commands, and 44px minimum targets.
- Non-goals:
  - Infinite canvas, two-page spread editing, presentation mode, or continuous
    multi-page scrolling.
  - A Zoom Writing Window or auto-advance writing flow in this delivery.
  - New PencilKit rendering, new drawing tools, handwriting recognition
    capability, or additional content types.
  - Full user-reorderable toolbar customization in the first delivery.
  - Editing or persisting preset slots across app launches.
  - A unified undo history for text, images, shapes, page operations, or lasso
    transforms; the first delivery labels the current draw/erase-only history
    honestly.
  - Cross-session viewport persistence, cloud sync, collaboration, phone, or
    Web editor work.
  - Redesigning the notebook library or changing paper dimensions when the
    device rotates.

## User Flow

1. The user opens a notebook at the current page.
2. A new editor session starts with Black Pen 3pt. Later page changes in the
   same editor session keep the active tool and each tool's Custom settings.
   The page opens in Fit Width on first visit.
3. The user writes immediately, taps another primary tool, or taps the active
   tool/property chip to open only that tool's settings.
4. Insert opens a labelled menu for Text, Image, and Shape. Selecting an item
   activates its existing placement flow.
5. Lasso selects ink and presents an upright contextual bar for recolor, Smart
   Ink, delete, and clear selection.
6. The current-page button opens Pages / Outline / Bookmarks. Wide layouts may
   pin the panel; compact layouts overlay it without permanently shrinking the
   canvas.
7. Pinch or explicit zoom commands change the viewport. Rotating or resizing
   the device preserves the current document focus and manual zoom intent.
8. Explicitly rotating a page rotates the entire page surface and its hit
   testing without changing any saved content coordinates.
9. Cancelled file pickers leave the workspace unchanged. Failed imports,
   exports, recording permissions, or saves explain the result and the next
   useful action.

## Acceptance Criteria

- [x] Pen, Highlighter, Eraser, Lasso, Insert, current tool properties, touch
  mode, undo, and redo are reachable without hidden horizontal scrolling at
  834×1194, 1194×834, and 600×800 logical layouts.
- [x] Every existing editor command remains reachable through a visible primary
  action or a labelled grouped menu.
- [x] The toolbar distinguishes primary tools, touch input mode, tool
  properties, and document commands instead of presenting them as one
  equivalent icon list.
- [x] Pen, Highlighter, Eraser, and Shape remember independent valid settings;
  switching tools never silently turns an eraser width into a pen width.
- [x] A complete preset changes tool type, color, and width together, and the
  duplicate floating favorites strip is removed. Manual changes are labelled
  Custom and do not mutate a fixed preset.
- [x] Text, Image, and Shape are available from Insert; Smart Ink is available
  from an ink-selection context.
- [x] The permanent bottom page strip is removed. The navigator preserves the
  current page and all existing page actions in wide and compact layouts.
- [x] `NotePage.width`, `NotePage.height`, page rotation, and all saved content
  coordinates remain unchanged by device rotation, Split View, keyboard
  appearance, or audio UI appearance.
- [x] Strokes, PDF backgrounds, templates, text, images, shapes, Smart Ink
  selection, lasso hit testing, and search highlights use the same document-to-
  viewport transform.
- [x] Fit Width is the first-visit writing mode; Fit Page is an explicit
  overview command; the first pan, zoom, or content gesture enters Custom mode
  at the current effective scale.
- [x] In custom zoom, a viewport resize preserves effective scale and the
  document point at the usable canvas center whenever clamping permits.
- [x] Explicit page rotation preserves the logical content point in view and
  follows one rule: fit modes remain fit modes and recompute from the rotated
  page bounds, while Custom preserves effective scale.
- [x] Returning to a page during the same editor session restores that page's
  viewport mode, scale, and focus.
- [x] All icon-only actions have unique semantic labels and tooltips, selected
  state is not conveyed by color alone, and important targets are at least
  44×44 logical pixels.
- [x] Existing blank, template, PDF, rotated, mixed-content, audio, search, and
  export workflows remain available.
- [x] Header actions are labelled `Undo ink stroke` and `Redo ink stroke`,
  follow the current page's draw/erase history, and never imply that lasso,
  text, image, shape, or page operations are reversible.
- [x] Lasso remains ink-only. Changing finger mode while ink is selected is
  blocked until the user clears or finishes that selection.
- [ ] A legacy-content compatibility decision and backup path are completed
  before the coordinate-space correction writes existing notebook files.
- [x] Missing page coordinate version is treated as legacy v0; empty v0 pages
  can upgrade losslessly, while non-empty unresolved v0 pages remain
  repository-enforced read-only until a raw archive and successful canonical
  conversion exist.
- [x] Negative, non-integer, or future page coordinate versions remain
  unsupported read-only and are never downgraded or overwritten.
- [ ] A raw archive drains pending saves and holds a notebook write lock until
  its manifest/checksums verify and the complete archive publishes atomically.

## Alternatives And Tradeoffs

- **Visual reskin over the current structure:** lower initial effort, but it
  preserves the hidden horizontal scroll, duplicated controls, and coordinate
  reliability defect. Rejected.
- **Keep every command visible and add toolbar customization:** useful later,
  but asks users to repair the default information architecture and still
  overloads compact layouts. Defer full customization until the default dock is
  proven.
- **Fit the whole page after every layout change:** maximizes overview, but
  changes writing scale and loses the user's working location. Keep as an
  explicit Fit Page action only.
- **Adopt a platform Pencil tool picker immediately:** offers strong Apple
  Pencil conventions, but does not cover InkNest's cross-platform content
  tools, page navigation, or current custom renderer. Treat it as a future
  Pencil-specific enhancement rather than the editor shell.
- **Switch to an infinite canvas or automatic two-page landscape spread:** may
  use landscape space differently, but conflicts with the accepted paged
  notebook model and changes export and navigation semantics. Out of scope.

## Dependencies And Risks

- The current editor screen combines document actions, page state, viewport
  state, media state, navigation, and most overlays in one large widget. The
  redesign should extract the shell, header, tool dock, navigator, and viewport
  controller before visual polish.
- Existing page JSON has no coordinate-space version or viewport metadata.
  Content created on a fitted surface cannot always be converted exactly,
  especially when one page was edited at multiple window sizes.
- A migration backup means a recoverable notebook archive containing the
  notebook index, original page JSON, assets, a manifest, and checksums. PDF
  export is useful for viewing but is not a recoverable editing backup. Archive
  creation must snapshot one consistent notebook state under a write lock and
  must not report success after a partial or failed publication.
- The current lowercase iOS bundle identifier,
  `com.example.inknestnotes`, gives the simulator a different application
  container from the earlier mixed-case identifier. The screenshot's current
  container has an empty notebook, while legacy prototype content may remain
  isolated in the old container. This identity history must be resolved before
  using current storage contents as migration evidence.
- The current undo/redo implementation covers draw/erase history only. The
  first delivery keeps that scope and labels it `Undo ink stroke` / `Redo ink
  stroke`; lasso deletion remains outside that history and still needs a
  dedicated confirmation follow-up.
- Moving document content under one canonical transform while projecting
  upright operation handles into viewport space requires focused hit-testing
  and export alignment tests before release.
- Large PDFs and dense pages need repaint isolation so the stable-coordinate
  surface does not regress Pencil latency.
- The work must add a page-level coordinate-space version and repository write
  gate before any canonical editor can save an unresolved legacy page.

## Open Decisions

- Before any legacy conversion, confirm whether current device storage contains
  irreplaceable handwritten notebooks. If it does, first create a recoverable
  raw notebook archive and choose a legacy compatibility strategy. If no
  irreplaceable data exists, the corrected coordinate-space version can become
  the baseline without a lossy best-effort migration.
- Confirm the permanent iOS bundle identifier and whether data in the old
  `com.example.inknestNotes` container must be recovered or imported. Do not
  interpret the new container's empty page as proof that no legacy data exists.
  The new bundle cannot directly read the old iOS container; recovery must use
  an old-identifier build, an extracted Simulator container, or a device backup
  before the identifier is retired.

## Delivery

- UI/UX spec:
  `docs/product/features/editor-workspace-redesign/UI_UX_SPEC.md`
- Implementation status: Core editor delivery completed on 2026-07-27 for new
  and canonical v1 pages.
- Delivered:
  1. Page-level coordinate versioning, legacy classification, repository write
     gates, and old/invalid JSON fixtures.
  2. Pure D↔R↔V transform math, Fit Width/Fit Page/Custom behavior, per-page
     session state, rotation, reflow, anchor, and clamp tests.
  3. A fixed-size document surface shared by page content and hit testing.
  4. A responsive document header, contextual tool dock, integrated presets,
     selection-context Smart Ink, on-demand overlay navigator, and collapsible
     wide Pages/Outline/Bookmarks panel.
  5. Responsive widget tests at 600×800, 834×1194, and 1194×834, plus
     canonical-coordinate persistence and read-only legacy UI coverage.
- Follow-up release work:
  1. Recover the old app container if it contains irreplaceable content.
  2. Build and verify a raw archive before offering any non-empty v0 conversion.
  3. Complete real-iPad Pencil latency, palm rejection, Split View, keyboard,
     large-PDF, golden, and operation-handle projection QA.
- Verification: Focused viewport, toolbar, responsive editor,
  coordinate-version model/repository, read-only UI, and migrated editor
  workflow tests pass. Full-suite and static-analysis results are recorded in
  `docs/development/STATUS.md`.
