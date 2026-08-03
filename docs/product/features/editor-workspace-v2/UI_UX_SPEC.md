# Editor Workspace V2 UI/UX Specification

- Status: Delivered
- Updated: 2026-08-03
- Product brief:
  `docs/product/features/editor-workspace-v2/PRODUCT_BRIEF.md`
- Affected surfaces: Editor document bar and contextual tool dock

## Recommendation

Keep the fixed paper viewport and two-row shell, but give the rows different,
predictable jobs. The first row reads as notebook navigation and page history;
the second reads as the current editing mode. Restore direct Pen/Highlighter
switching and move remembered presets out of persistent chrome.

The design improves interaction through hierarchy and shorter paths rather
than adding new controls or another visual layer over the paper.

## User Flow

1. From the library, enter a notebook. Focus order starts with Back, Pages,
   notebook title/page position, then document actions.
2. Pen is ready. Tap Highlighter, Eraser, Lasso, or Insert directly.
3. Tap an already-selected Pen, Highlighter, or Eraser control to open
   settings; use the style preview for the same settings and for Shape.
4. Change a preset, color, or width. The panel updates the page tool immediately
   and can be dismissed without changing canvas focus.
5. Undo/Redo from the document row. Search and More remain at the trailing edge.
6. On cancellation or picker failure, retain tool, viewport, and page content;
   existing snackbars explain errors.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Default writing | Pen selected; quiet style preview; Finger writes quiet | Draw, switch tool, open Pages/Search/More | Selected state uses fill and semantics |
| Another tool selected | Exactly one primary editing tool selected | Tap again for properties when configurable | Tool icon and style preview update |
| Properties open | Anchored card at ≥720; sheet below 720 | Preset, style, color, width, eraser/shape options | Outside tap/Close dismisses; edits remain applied |
| No ink history | Undo/Redo disabled in document bar | Other actions remain available | Disabled appearance and semantics |
| Read-only legacy page | Tool dock dimmed and blocked; document navigation remains active | Pages, search, view/export actions | Existing write-protection explanation remains |
| Busy audio/export/import | Existing progress/status feedback | Unrelated navigation where safe | Existing error snackbar/retry path |

## Layout And Components

### Document bar

- Height: 52px, existing chrome surface and divider.
- Leading order:
  1. Back, 48px navigation target.
  2. Pages button, 44px target with page-count badge.
  3. Notebook context: title on the first line, `Page n of total` below.
- Trailing order:
  1. Undo ink stroke.
  2. Redo ink stroke.
  3. Search notebook.
  4. More editor actions.
- Record, Export, and all existing lower-frequency actions remain in More.
  Active recording continues to use its existing visible status banner.
- At compact widths, the notebook title flexes and truncates before any action
  target shrinks. No title interaction duplicates the Pages entry.

### Contextual tool dock

- Height: 52px, visually separated from the document bar by the existing
  divider; centered at regular/wide widths and left-balanced in Split View.
- Persistent order:
  1. Pen.
  2. Highlighter.
  3. Eraser.
  4. Lasso.
  5. Insert.
  6. Divider.
  7. Active style preview/properties.
  8. Divider.
  9. Finger mode.
- Do not render fixed preset buttons or a presets dropdown in this row.
- Labels may appear only when width allows them without displacing 44px targets;
  icon tooltips and semantics remain at every width.
- Pen and Highlighter show independent selected states. An already-selected
  Pen, Highlighter, or Eraser opens the same properties surface as the style
  preview.
- Lasso remains selection-only and has no empty properties panel.
- Insert retains Text, Image, and Shape. Shape selection makes Insert selected;
  its style remains editable from the style preview.

### Reused components and copy

- Reuse `EditorChrome`, `EditorWorkspaceTokens`, existing properties panel,
  Insert/Finger popovers, snackbar/dialog styles, and viewport chrome.
- Existing user-facing labels remain: `Pen`, `Highlighter`, `Eraser`, `Lasso`,
  `Insert`, `Finger writes`, `Finger moves`, `Undo ink stroke`, and
  `Redo ink stroke`.

## Input And Responsive Behavior

- Pencil: changing chrome never captures or delays a stroke outside its target;
  current Pencil/finger gesture ownership remains unchanged.
- Finger: Finger writes remains quiet; Finger moves remains strongly selected.
- Mouse/trackpad: every icon exposes a tooltip; hover/focus order follows the
  visual order.
- Keyboard: existing keyboard behavior remains; Undo/Redo buttons expose honest
  ink-only semantics until unified history exists.
- 600px Split View: all targets remain at least 44px; no horizontal scrolling.
- 834px portrait and 1194px landscape: tool cluster remains centered and no
  preset dots compete with tool icons.
- Phone/Web are out of scope.

## Accessibility

- Each primary tool is a semantic button with selected state and a unique
  label; Pen and Highlighter are announced separately.
- Disabled Undo/Redo remain discoverable through their tooltips and logical
  position.
- Meaning is not encoded by color alone; selected fill, icon state, and
  semantics agree.
- Text scaling may truncate the notebook title and optional tool labels, but
  never clips or removes the action targets.
- Pages, properties, and menus provide non-gesture alternatives to navigation,
  zoom, and editing configuration.

## UI Acceptance Criteria

- [x] Document and editing actions are separated according to the specified
  hierarchy at 600×800, 834×1194, and 1194×834.
- [x] Pen and Highlighter switch directly and expose separate semantics.
- [x] Active configurable-tool tap and style-preview tap open the same
  contextual settings.
- [x] Presets remain inside settings and do not render persistently.
- [x] Read-only, busy, selected, disabled, and cancellation behavior remains
  coherent with existing editor feedback.
- [x] No supported layout overflows or introduces a scrolling toolbar.

## Verification

- Widget tests: direct Pen/Highlighter switching, selected-tool settings,
  presets inside properties, Undo/Redo document placement, and absence of
  persistent presets.
- Responsive tests: 600×800, 834×1194, and 1194×834; semantics and minimum
  target checks.
- Visual check: 11-inch iPad landscape render before and after implementation.
- Manual device checks: Pencil latency, palm rejection, rotation, and Split
  View remain part of release QA.

## Implementation Review

- Status: Delivered
- Intentional deviations: None. Shape settings use the explicit style preview
  because Shape is selected through Insert rather than a persistent primary
  tool button.
