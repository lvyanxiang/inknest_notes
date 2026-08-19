# Text Box Interaction V2 UI/UX Specification

- Status: Delivered
- Updated: 2026-08-19
- Product brief: `docs/product/features/text-box-font-and-resize/PRODUCT_BRIEF.md`
- Affected surfaces: Paged editor and infinite-canvas text boxes

## Recommendation

Use a canvas-object interaction instead of a permanently decorated input. The
paper remains clean until a text object is selected; formatting and destructive
actions live in a floating toolbar outside the content, while direct handles
own move and resize gestures.

## User Flow

1. Text tool + paper tap creates an empty editing box with `Type text` as a
   hint and opens the keyboard.
2. Type normally. Return inserts a manual line break; text also wraps at the
   persisted width.
3. Use the floating toolbar for move, font, size, color, alignment, and More.
4. Drag either side handle to resize width. Text reflows live.
5. Tap outside or Done to finish and hide chrome. An untouched empty box is
   discarded.
6. Tap existing text once to select and again to edit; More contains Delete.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Idle | Text only | Tap while Text is active | Selection frame appears |
| Selected | Light frame, side handles, floating toolbar | Move, resize, format, delete, tap text to edit | Changes preview immediately; gesture completion records undo |
| Editing | Caret, light frame, handles, toolbar with Done | Type, select text, format, move, resize, finish | One editing session records one undo entry |
| New empty | Hint, caret, editing chrome | Type or dismiss | Dismiss removes the unused object without persisting hint text |
| Disabled/read-only | Text only | None | Canvas remains readable and drawable according to the active tool |

## Layout And Components

- Idle text uses no surface fill or shadow.
- Selected/editing frames use the existing primary color at low visual weight.
- Side handles have small visible circles with 44px transparent hit targets.
- The toolbar is positioned above the object when space permits and below it
  near the top page edge. It uses 44px controls and moves Delete into More.
- Font names render in their real bundled family. Size uses a short preset
  list; color uses existing ink colors; alignment supports left/center/right.

## Input And Responsive Behavior

- Pencil/touch: text controls own their gestures; otherwise the active canvas
  tool keeps pointer ownership. Dragging text never draws ink.
- Mouse/trackpad: move and horizontal-resize cursors communicate ownership.
- Keyboard: Return adds a line, Escape/Done finishes when available, and native
  text selection remains inside editing state.
- iPad portrait/landscape/Split View: toolbar may overflow the narrow object
  but remains clipped to the page viewport; page-edge placement flips below.
- Infinite canvas uses the same controls after world/screen coordinate mapping.

## Accessibility

- Every icon-only control has a tooltip and semantic name.
- Hit targets are at least 44 logical pixels; selected state is communicated by
  border and semantics rather than color alone.
- Font, size, color, and alignment menus expose checked selection state.
- Delete remains available through a labelled menu, not gesture-only.

## UI Acceptance Criteria

- [x] Reading state shows only content.
- [x] Selection and editing are visibly and behaviorally distinct.
- [x] Empty creation, outside completion, keyboard editing, movement, resizing,
  formatting, and deletion have deterministic outcomes.
- [x] Paged and infinite-canvas behavior matches at supported zoom levels.
- [x] All actions have accessible non-ambiguous controls and undo recovery.

## Verification

- Widget tests: three states, creation/cancellation, tap transitions, every
  formatting group, move/resize, delete, and transaction undo/redo.
- Persistence/export tests: alignment and existing font migration round-trip;
  PDF export uses the same alignment and width.
- Responsive/semantic tests: 44px targets and compact page-edge toolbar.
- Manual device checks: keyboard, Pencil/finger gesture ownership, portrait,
  landscape, and Split View.

## Implementation Review

- Status: Delivered
- Intentional deviations: None.
