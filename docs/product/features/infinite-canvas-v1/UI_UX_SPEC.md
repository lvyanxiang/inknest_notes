# Infinite Canvas V1 UI/UX Specification

- Status: Delivered
- Updated: 2026-08-04
- Product brief: `docs/product/features/infinite-canvas-v1/PRODUCT_BRIEF.md`
- Affected surfaces: Library create flow, notebook routing, infinite editor

## UX Recommendation

Keep notebook type explicit at creation and keep the two editor models
visually related but operationally separate. Infinite canvas should feel like
the existing writing workspace without showing page-only controls.

## Primary Flow

1. Tap New notebook.
2. Choose Paged notebook or Infinite canvas from a two-card sheet; close or
   outside-tap cancels without creation.
3. Infinite canvas opens centered at world origin with Pen ready.
4. Write with Pencil/mouse or Finger writes. Use two fingers or Finger moves to
   explore the canvas.
5. Change background from the document bar; undo/redo from the same bar.
6. Leave the editor. Reopening restores content, background, focus, and zoom.

## State Matrix

| State | Visible UI | Behavior |
|---|---|---|
| Empty canvas | Repeating background, Pen selected | First stroke creates content in world coordinates |
| Writing | Tool dock plus live stroke | Pencil/mouse writes; Finger writes follows assist setting |
| Finger moves | Pan mode selected | One finger pans; two fingers pan/zoom |
| Pinch active | Canvas transforms; no live stroke | Any provisional touch stroke is cancelled |
| No history | Undo/Redo disabled | Other tools remain available |
| Saving | No blocking overlay for normal edits | Latest mutation is serialized safely |
| Reopened | Last focus and zoom restored | Content remains at identical world coordinates |

## Layout

- Use the same two fixed 52dp editor rows as paged notebooks: notebook
  identity plus document actions in the top row, and Pen, Highlighter, Eraser,
  Lasso, Insert, properties, and Finger mode in the bottom row.
- Keep the top row's action order as Undo, Redo, Canvas background, and Fit
  content. A width-derived capacity keeps the first actions direct and moves
  the rest into a labelled More menu.
- At compact phone widths, keep the document identity visible, expose Undo and
  Redo directly, and place Canvas background and Fit content in More. At
  widths below 360dp, the drawing row may scroll horizontally so no core tool
  is silently removed.
- No Pages, page count, Add page, Outline, Bookmarks, PDF import, or page export
  actions.
- The drawing row reuses the shared EditorToolbar, including Lasso and Insert
  for the delivered rich canvas content.
- Canvas occupies the remaining area and clips rendering to the viewport.

## Interaction And Accessibility

- Scale is bounded to prevent losing content or numerical instability.
- Recenter frames existing stroke bounds; on an empty canvas it returns to the
  world origin.
- Every icon-only control has a tooltip and at least a 44px target.
- Pointer ownership is exclusive: a pointer sequence draws, pans, or pinches,
  never more than one.
- 600px Split View, 834px portrait, and 1194px landscape must not overflow.

## UI Acceptance Criteria

- [x] Creation choices are readable, keyboard/focus reachable, and cancellable.
- [x] Infinite editor has no paged-only controls.
- [x] Tool selection, disabled history, background selection, and Finger mode
  have visible state beyond color alone.
- [x] Pinch/pan never commits accidental ink.
- [x] Recenter and restored viewport keep existing content recoverable.
- [x] Supported iPad widths render without toolbar overflow.
- [x] Infinite-canvas editing and document controls use the same two-row
  editor chrome as paged notebooks; no page-only controls appear.

## Verification

- Model JSON compatibility and repository persistence tests.
- Widget tests for creation routing, drawing, erase, undo/redo, gesture
  ownership, background selection, and viewport restoration.
- Full paged regression suite and `flutter analyze`.

## Implementation Review

- Status: Delivered
- The earlier single-bar infinite-canvas header was superseded by the shared
  two-row editor chrome so phone and tablet layouts keep the same vertical
  rhythm and responsive More behavior as paged notebooks.

## V2 Shared Editing UI

- Status: First delivery slice delivered.
- Show Lasso and Insert in the same middle tool group as paged notebooks.
- Insert exposes Text, Image, and Shape with the existing labels and property
  surfaces; inserting content keeps the current viewport stable.
- Text mode taps create an empty text box in editing state at world
  coordinates. Existing text is chrome-free when idle, uses first-tap
  selection and second-tap editing, and exposes an external toolbar for move,
  font, size, color, alignment, width resize, and deletion. Completed edit,
  move, resize, format, creation, and deletion actions enter history as atomic
  undo/redo transactions without changing the canvas transform.
- Inserted images appear at the viewport focus and expose move, resize, and
  delete handles without adding finite canvas boundaries.
- Shape mode draws directly in world coordinates and retains two-finger
  gesture cancellation.
- Lasso temporarily owns one-finger input and disables Finger moves; selection
  controls stay upright in viewport chrome while selected ink remains in world
  coordinates.
- At compact widths, tool labels and notebook identity collapse before Lasso,
  Insert, or core document actions are removed.
