# Text Box Font And Resize UI/UX Specification

- Status: Delivered
- Updated: 2026-08-19
- Product brief: `docs/product/features/text-box-font-and-resize/PRODUCT_BRIEF.md`
- Affected surfaces: Paged editor and infinite-canvas text boxes

## Recommendation

Replace the ambiguous handwriting-style toggle with an explicit font menu and
add a visible horizontal resize handle. Width remains stable while typing, so
automatic wrapping is controlled by direct resizing; Return continues to add
an intentional line break.

## User Flow

1. Insert or focus a text box.
2. Type normally; text wraps at the current box width.
3. Open Choose font and select Default, 刘建毛草, 龙藏, or 芝麻行.
4. Drag Resize text box horizontally until the desired wrapping is visible.
5. Move or delete with the existing controls.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Editing | Border, move, font, resize, delete, text caret | Type, select font, move, resize, delete | Changes appear immediately |
| Font menu open | Current font is checked | Choose any listed font or dismiss | Selected font applies immediately |
| Resizing | Horizontal resize cursor/handle | Drag left or right | Text reflows live; minimum and page edge are enforced |
| Legacy note | Default or migrated real font | Normal editing actions | No simulated handwriting styling remains |

## Layout And Components

- Placement and hierarchy: move on the left; font, resize, and delete on the
  right of the text-box header.
- Reused components: Material popup menu, icon buttons, current text field,
  bundled handwriting fonts.
- User-facing copy: `Choose font`, `Resize text box`, `Delete text box`.

## Input And Responsive Behavior

- Pencil and touch: header gestures own move/resize and never draw ink.
- Mouse/trackpad and keyboard: resize handle uses a horizontal-resize cursor;
  keyboard Return inserts a line break.
- iPad portrait/landscape or split view: page text boxes clamp to the remaining
  page width and retain a usable minimum width.
- Phone/Web: shared Flutter behavior; no platform-specific font simulation.

## Accessibility

- Semantics and focus: every icon-only control has a tooltip; menu items expose
  full font names and selected state.
- Text scaling and contrast: the editor field remains multiline and uses the
  existing surface/border contrast.
- Non-gesture alternative: the font menu is keyboard accessible; resizing is
  primarily direct manipulation in this version.

## UI Acceptance Criteria

- [x] Font selection is explicit and the current choice is visible in the menu.
- [x] Resize gestures reflow text without moving the text box.
- [x] Controls fit at the minimum text-box width without clipping.
- [x] Paged and infinite-canvas text boxes behave consistently.

## Verification

- Widget tests: select every real font, resize width, verify wrapping control
  state, persistence, and legacy migration.
- Responsive/semantic/golden tests: focused widget coverage for tooltips and
  minimum-width controls; no golden required.
- Manual device checks: Pencil/finger gesture ownership and keyboard wrapping
  on iPad portrait, landscape, and Split View.

## Implementation Review

- Status: Delivered
- Intentional deviations: None.
