# Android Phone UX Polish UI/UX Specification

> The single-page phone viewport and top-anchoring behavior in this historical
> specification was superseded on 2026-09-07 by the cross-device continuous
> paged editor in `../continuous-paged-editor/UI_UX_SPEC.md`.

- Status: Delivered
- Updated: 2026-09-07
- Product brief: `docs/product/features/android-phone-ux-polish/PRODUCT_BRIEF.md`
- Affected surfaces: Android phone library, paged editor export, lasso, text boxes

## Recommendation

Treat a phone as a first-class compact surface rather than a scaled tablet.
Preserve feature parity and the bookshelf metaphor, while adapting only the
surrounding header and dense contextual controls to keep touch targets stable.

## User Flow

1. Enter the library and scan the existing bookshelf of folders and notebooks.
2. Tap a spine to open, or its existing actions control to manage it.
3. In the editor, choose export options from whole-word chips that can wrap.
4. Choose Shape from the same peer-level toolbar as Pen and Highlighter, then
   open the clearly labeled `Shape · <type>` properties entry to choose a
   preset (Line, Arrow, Rectangle, Ellipse, or Triangle) or `Auto shape`.
5. Select ink and use a compact lasso bar; recoloring opens one palette menu.
6. Erase ink locally or touch a geometric shape/image to remove that object;
   undo restores the complete erase action.
7. Insert/select typed text and use controls that remain screen-sized while the
   paper is fit into the phone viewport.
8. Cancel any sheet/dialog or clear a selection without changing content.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Phone library | Compact heading, search/filters, existing spine bookshelf | Open, actions, search, sort, create/import | Existing local persistence and navigation |
| Empty/search | Existing focused empty state | Create/import or clear query | No destructive state change |
| Export default | Scope and quality choice chips | Change options, cancel, export | Summary/quality description update immediately |
| Export page error | Page field and inline error | Correct input or cancel | Export remains disabled |
| Lasso selected | Count, Beautify, palette, delete, clear | Act on selection | Existing undo stack or clear selection |
| Eraser active | Ink brush plus atomic shape/image hit behavior | Erase ink or remove a touched object | One gesture is one undoable content mutation |
| Text selected/editing | Screen-stable object toolbar and handles | Move, format, edit/done, delete, resize | Existing transaction undo and empty-box cancellation |

## Layout And Components

- Placement and hierarchy:
  - Under 480dp, remove the decorative library mark/brand line from the top row
    and prioritize location title, summary, and core actions.
  - Use one shared phone/tablet command row: keep search as the flexible primary
    command, remove the nested outer command surface, and place a compact sort
    control plus matching 44dp folder/archive buttons beside it.
  - The phone keeps the existing packed spine rows and their title, metadata,
    open, and action behavior.
- Reused components: existing search, sort, account, notebook/folder action menus,
  dialog/sheet components, and editor callbacks.
- New component or pattern: compact library header and a single phone lasso
  color palette action; Shape is a peer-level tool and its type settings stay
  visible as an explicit entry; no alternate library card presentation.
- User-facing copy: notebook metadata is “N pages · Paged” or “Infinite canvas”.

## Input And Responsive Behavior

- Pencil and touch: whole cards open; action controls, lasso actions, text actions,
  and resize handles target at least 44dp on screen.
- Eraser: crossing ink removes only the touched ink segment; touching a shape or
  image removes that whole object, and the complete gesture is undoable.
- Mouse/trackpad and keyboard: existing bookshelf hover/focus behavior remains at
  480dp and wider; phone cards retain semantics and tooltips.
- iPad portrait/landscape or split view: unchanged existing bookshelf/editor.
- Phone/Web, if in scope: compact behavior is width-driven below 480dp so narrow
  Web windows fail safely as well; physical verification targets Android.

## Accessibility

- Semantics and focus: spines expose explicit “Open …” labels; their action
  menus remain separately labeled.
- Text scaling and contrast: titles use two-line ellipsis; chips wrap as complete
  controls; palette choices include text semantics/tooltips.
- Non-gesture alternative: all long-press functionality remains available from
  visible action menus; palette colors are available through a button menu.

## UI Acceptance Criteria

- [x] 360dp phone library has no clipped heading fragments and retains the
      bookshelf/spine presentation.
- [x] Phone and tablet library commands keep search primary and present sort plus
      folder/archive actions together in one compact row.
- [x] Export dialog at 360dp has no overflow and no per-letter wrapping.
- [x] Lasso selection at 360dp has no yellow/black overflow stripe.
- [x] Text toolbar actions render at least 40dp and target approximately 44dp on
      the physical phone at the initial fitted page scale.
- [x] A contained Fit Width page on a narrow phone is top-anchored with the
      standard inset; tablet centering behavior and page/document coordinates
      remain unchanged.
- [x] 600dp layout still renders bookshelf rows and existing actions.
- [x] Destructive confirmation is visually distinct and empty name save is disabled.
- [x] Erasing a shape or image is atomic and undoable; ink remains locally erasable.
- [x] Pen, Highlighter, and Shape are peer-level entries; Shape settings are
      explicitly labeled with the current shape type.
- [x] Switching to Shape gives the properties control a brief scale/rotation
      attention cue and a non-visual “Tap to choose a shape type” hint.

## Verification

- Widget tests: phone library breakpoint, export narrow dialog, lasso narrow bar,
  scaled text controls, empty-name validation, and existing broad suite.
- Responsive/semantic/golden tests: 360x800 and existing 600x800 assertions; no
  framework exceptions/overflow.
- Manual device checks: V2309A hot reload after restoration; no new screenshot
  capture was requested.

## Implementation Review

- Status: Delivered
- Intentional deviation: the initial phone card-grid experiment was rolled back
  after user review; the bookshelf remains the deliberate product identity.
