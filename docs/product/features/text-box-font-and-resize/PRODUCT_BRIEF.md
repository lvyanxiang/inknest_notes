# Text Box Interaction V2 Product Brief

- Status: Delivered
- Size: Medium
- Updated: 2026-08-19
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md#post-mvp-4-rich-notes`

## Problem

Typed notes currently behave like permanently open form fields: every box
always shows a surface, border, and compact controls, while selection and
editing are indistinguishable. Empty boxes persist placeholder content,
formatting is incomplete, and undo is either absent on paged notes or records
every intermediate update on infinite canvas.

## Recommended Outcome

Treat text as a first-class canvas object with three states: idle, selected,
and editing. Idle text leaves the paper visually clean. Selection exposes a
light frame, large resize handles, and an external object toolbar. Editing adds
the caret and keyboard without changing the object's layout. Text changes,
movement, resizing, formatting, creation, and deletion use coherent undo
transactions.

## Scope

- In scope: paged and infinite-canvas text boxes; idle/selected/editing states;
  empty placeholder behavior; tap-outside completion; move and width resize;
  real font, size, color, and alignment controls; deletion; persistence; PDF
  export; and transaction-level undo/redo.
- Non-goals: rich-text spans, rotation, layer ordering, locking, text flowing
  between pages, imported fonts, or changing ML Kit Smart Ink/Beautify.

## User Flow

1. Choose Text and tap the paper to create an empty box in editing state.
2. Type and format from the floating object toolbar; drag a side handle to
   control wrapping or the move handle to reposition the box.
3. Tap outside to finish. Empty new boxes disappear; non-empty boxes become
   clean, chrome-free text.
4. Tap an existing box to select it and tap again to edit. Undo restores one
   completed input, move, resize, format, creation, or deletion action.

## Acceptance Criteria

- [x] Idle text displays no permanent card, border, toolbar, or controls.
- [x] One tap selects an existing text box; a second tap enters editing.
- [x] New boxes start empty with a non-persisted hint and immediate keyboard
  focus; tapping outside removes an unused empty box.
- [x] Selected/editing boxes provide at least 44px move/resize/action targets
  and an external toolbar for font, size, color, alignment, and more actions.
- [x] Width resizing controls wrapping without changing font size.
- [x] Paged and infinite-canvas editors use the same interaction state model.
- [x] Creation, deletion, a continuous edit session, and each complete
  move/resize gesture are atomic undo/redo operations.
- [x] Existing font/style migration, persistence, thumbnails, PDF export, and
  Smart Ink continue to work.

## Alternatives And Tradeoffs

- Keep improving the permanent header: rejected because it cannot provide a
  clean reading state or clear gesture ownership.
- Enter editing on the first tap: rejected because selection, movement, and
  object formatting would remain easy to trigger accidentally.

## Dependencies And Risks

- The shared text layer needs explicit parent-owned selected/editing state.
- Paged editor history must expand from stroke-only snapshots to page-content
  snapshots without breaking existing Smart Ink and eraser behavior.
- Floating controls must stay usable near page edges and under canvas zoom.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/text-box-font-and-resize/UI_UX_SPEC.md`
- Implementation status: Delivered
- Verification: 269 Flutter tests, `flutter analyze`, and `git diff --check`
