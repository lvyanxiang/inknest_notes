# Shape Recognition

- Status: V2 core delivered
- Size: Medium
- Updated: 2026-09-07

## Problem

The current Shape tool only creates a selected primitive from a drag. A user
who sketches a circle, triangle, or uneven line must manually choose a type and
cannot turn a natural one-stroke gesture into clean geometry.

## Recommended Outcome

Keep the existing precise preset mode and add an explicit local Auto shape mode.
In Auto shape mode, one freehand path is classified as a line, arrow, ellipse,
rectangle, triangle, diamond, or polygon when confidence is sufficient;
otherwise the original path is retained as ink. Existing page data remains
compatible.

V2 extends this into the normal Pen workflow: when Draw and hold is enabled,
pausing at the end of a recognizable stroke previews a clean shape, continued
pointer movement adjusts it, and lifting commits it. The preference remains
visible and reversible so handwriting is never converted without an explicit
setting.

## Scope

- In scope:
  - Auto shape mode in the existing Shape properties surface.
  - Local deterministic recognition for lines, arrows, ellipses/circles,
    rectangles, triangles, diamonds, and polygons.
  - A visible raw-path preview while drawing.
  - Fallback to an ordinary pen stroke when recognition is inconclusive.
  - Triangle persistence, rendering, hit testing, export, and undo/redo.
  - Paged and infinite-canvas editor paths.
  - V2 Draw and hold preference for Pen on iOS/iPadOS and Android.
  - A 500ms stationary hold before conversion, clean preview, continued-size
    adjustment, and lift-to-commit.
  - Additive arrow, diamond, and polygon recognition/storage/render/export.
- Non-goals:
  - Cloud or ML recognition.
  - Multi-stroke shape grouping or connector routing.
  - Rewriting existing strokes or existing shape objects.
  - Shape vertex-selection/editing; this requires a unified object-selection
    model rather than overloading the current ink-only lasso.

## Acceptance Criteria

- [x] Preset mode behaves exactly as before, including arrow and line tools.
- [x] Auto shape is discoverable from Shape properties and is not silently
      enabled for ordinary Pen writing.
- [x] A sufficiently straight open path becomes a line.
- [x] A closed path becomes an ellipse, rectangle, or triangle when its outline
      supports that classification.
- [x] An inconclusive path remains a pen stroke and is undoable.
- [x] Recognized shapes are persisted, reloadable, erasable, undoable, and
      exported without changing existing page coordinates.
- [x] Multi-touch cancels the active recognition gesture without committing
      partial content.
- [x] Pen settings expose Draw and hold and allow it to be disabled.
- [x] Holding a recognizable Pen stroke for 500ms replaces the raw preview with
      clean geometry; moving while held adjusts it and lifting commits it.
- [x] A normal quick Pen stroke remains ink with no recognition delay.
- [x] Arrow, diamond, and polygon results persist, erase, undo, and export like
      existing shapes.
- [x] The same shared behavior works in paged and infinite-canvas editors on
      iOS/iPadOS and Android.

## Risks

- Heuristic recognition can misclassify rough handwriting. Keep Auto shape
  explicit, use conservative thresholds, and preserve the raw-stroke fallback.
- Adding persisted enum values requires every renderer, hit tester, and exporter
  to handle them while old JSON remains readable.

## Delivery

- UI/UX spec: `UI_UX_SPEC.md`
- Implementation status: V1 and V2 core delivered; multi-stroke grouping and
  unified shape-object editing are recorded for V2.1.
- Verification: `flutter analyze`; full `flutter test` suite (309 tests).
