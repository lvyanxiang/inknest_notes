# Infinite Canvas V1 UI/UX Specification

- Status: Delivered
- Updated: 2026-08-03
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

- Document bar: Back, notebook title with `Infinite canvas` subtitle, Undo,
  Redo, background menu, and recenter action.
- No Pages, page count, Add page, Outline, Bookmarks, PDF import, or page export
  actions.
- Tool dock reuses Pen, Highlighter, Eraser, properties, and Finger modes.
  Lasso and Insert are hidden until their canvas-specific implementations exist.
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

## Verification

- Model JSON compatibility and repository persistence tests.
- Widget tests for creation routing, drawing, erase, undo/redo, gesture
  ownership, background selection, and viewport restoration.
- Full paged regression suite and `flutter analyze`.

## Implementation Review

- Status: Delivered
- Intentional deviations: None.
