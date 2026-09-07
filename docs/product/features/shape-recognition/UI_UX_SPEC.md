# Shape Recognition UI/UX Specification

- Status: V2 core delivered
- Updated: 2026-09-07
- Product brief: `PRODUCT_BRIEF.md`

## Recommendation

Reuse the existing Shape properties entry. Add a compact Creation choice with
`Preset` and `Auto shape`; do not open a new modal while drawing. Auto shape is
explicitly opt-in so normal Pen handwriting never changes unexpectedly.

V2 adds a `Draw and hold` switch to Pen properties. It is enabled by default
for new sessions, remains remembered independently with Pen settings, and can
be disabled without changing Shape mode.

## Flow

1. Choose Insert → Shape.
2. Open the visible `Shape · Line` properties entry.
3. Choose `Auto shape` under Creation.
4. Draw one stroke and lift the stylus.
5. Show the raw stroke during capture; on completion replace it with a clean
   shape when recognized, or keep it as ink when uncertain.
6. Use the existing Undo to reverse either result.

### Pen Draw and hold

1. Draw a recognizable line or closed shape with Pen.
2. Keep the pointer still for 500ms at the end.
3. The raw path changes to a clean preview without a modal or progress state.
4. Move while still touching to adjust the preview; lift to commit.
5. Lift before the hold threshold to keep normal ink.

## States

| State | Visible behavior | Recovery |
|---|---|---|
| Preset | Drag creates the selected primitive | Existing behavior |
| Auto selected | `Shape · Auto` summary and explanatory helper text | Switch back to Preset |
| Drawing | Raw path follows the pointer | Multi-touch cancels |
| Recognized | Clean geometry commits atomically | Undo restores the previous page |
| Uncertain | Raw path commits as pen ink | Undo removes the fallback stroke |
| Pen hold pending | Normal raw ink remains visible | Move or lift to continue normal writing |
| Pen hold recognized | Clean preview replaces raw path | Move to adjust; lift to commit; multi-touch cancels |

## Layout and accessibility

- Creation choices live below the shape-type choices in the existing properties
  sheet/card; targets remain at least 44dp.
- Auto shape exposes semantics explaining: “Draw one stroke and release to
  convert it into a clean shape.”
- The selected mode is communicated by label, icon, and selected state, not
  color alone.
- The raw preview uses the active color and width, with no blocking progress
  indicator.

## Input and edge cases

- Pencil, mouse, and touch use the same recognition thresholds; Finger moves
  continues to own touch panning when enabled.
- Auto recognition is single-stroke in this delivery. Open curves, scribbles,
  and self-intersections stay as ink.
- Existing `Line`, `Arrow`, `Rectangle`, and `Ellipse` shapes remain readable;
  `Triangle`, `Diamond`, and `Polygon` are additive.
- Draw and hold is available in both paged and infinite-canvas editors through
  shared Pen properties. It never runs for Eraser, Lasso, Text, or finger pan.
- Shape selection/vertex editing and multi-stroke grouping remain a V2.1
  follow-up because the current lasso intentionally selects ink only.

## Verification

- [x] Unit tests cover line, rectangle, ellipse, triangle, and inconclusive paths.
- [x] Widget tests cover entering Auto shape and preserving Preset behavior.
- [x] Existing editor, storage, export, and undo tests remain green.
- [x] Widget tests cover quick Pen ink, held conversion, live adjustment,
      disabling Draw and hold, and infinite-canvas conversion.
- [x] Unit tests cover arrow, diamond, polygon, and polygon JSON round trips.

## Implementation Review

- Status: V2 core delivered
- Intentional boundary: this release recognizes one stroke at a time;
  multi-stroke grouping and connector routing remain out of scope.
