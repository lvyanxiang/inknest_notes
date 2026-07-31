# Ink Beautify Strokes Product Brief

- Status: Delivered
- Size: Medium
- Updated: 2026-07-30

## Problem

Users want selected rough handwriting to become neat **ink strokes**, not an
editable text box. The previous Smart Ink path recognized text and inserted a
handwriting-style `NoteTextBox`, which missed the desired output type.

## Recommended Outcome

1. Keep OCR + optional text correction as the content source.
2. Let the user pick one of three bundled OFL handwriting fonts:
   刘建毛草 / 龙藏 / 芝麻行.
3. Convert the confirmed text into vector-like polylines and write them as
   normal pen `Stroke`s fitted into the selection bounds.
4. Default to replacing the selected ink; keep Undo via page save/history of
   strokes on the page.

## Scope

- In scope: lasso Beautify dialog font picker, font assets, glyph→stroke
  generator, replace/keep-original checkbox, tests.
- Non-goals: personal style cloning, searchable hidden text sidecar, math,
  template stroke libraries, geometric-only smooth without recognition.

## Acceptance Criteria

- [x] Three bundled fonts are selectable in the Beautify dialog with preview.
- [x] Confirming Beautify inserts strokes (not a text box) near the selection.
- [x] Successful recognition hides the text field; Edit text is optional.
- [x] Lasso uses drag-box / tap selection instead of freeform polygon tracing.
- [x] Recognition failure still allows manual text entry before redraw.
- [x] Generator unit tests cover all three font families.
