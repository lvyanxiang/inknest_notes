# Android Phone UX Polish Product Brief

> The single-page phone viewport and top-anchoring decision in this historical
> brief was superseded on 2026-09-07 by the cross-device continuous paged
> editor in `../continuous-paged-editor/PRODUCT_BRIEF.md`.

- Status: Delivered
- Size: Medium
- Updated: 2026-09-07
- Roadmap link: User-requested Android phone usability pass

## Problem

InkNest's core flows work on a 360dp Android phone, but several layouts still
behave like reduced tablet UI. Export choices break into letter-by-letter
labels, the lasso action bar overflows, and text-object controls shrink with
the page. The initial audit also questioned spine title legibility; user review
confirmed that the bookshelf identity should remain, so the card substitution
was rolled back.

## Recommended Outcome

Give Android phone users a legible, touch-safe presentation of the existing
local-first library and editor. Keep the existing bookshelf/spine notebook list
at every width, while using a compact phone header, responsive choice controls
and contextual toolbars, and screen-stable text controls.

## Scope

- In scope:
  - Android phone library header while retaining the existing bookshelf.
  - Export scope and quality controls on narrow screens.
  - Lasso selection actions on narrow screens.
  - Text-box toolbar and resize target sizing while a page is scaled down.
  - Explicit shape-type discovery when entering the Shape tool.
  - Eraser behavior for ink, geometric shapes, and imported images with undo.
  - Empty-name validation and destructive-action emphasis.
  - Targeted widget tests and physical Android regression screenshots.
- Non-goals:
  - iPad/tablet bookshelf redesign.
  - Cloud sync, account protocol, notebook storage, or PDF export changes.
  - Infinite-canvas information architecture changes.
  - Localization or release-readiness/legal completion.

## User Flow

1. The user opens the library on an Android phone and sees the familiar
   notebook/folder bookshelf with its existing spine actions.
2. The user opens a notebook and uses the same editor tools as before.
3. Narrow export and lasso controls adapt without clipped content or overflow.
4. Text editing controls remain large enough to identify and tap at Fit Page or
   Fit Width.
5. Cancel and back continue to preserve content; destructive actions retain a
   confirmation and use danger styling.

## Acceptance Criteria

- [x] At every width, including below 480dp, the library retains the existing
      bookshelf/spine list, open targets, and action menus.
- [x] The library heading and summary no longer collapse to unusable fragments
      on a 360dp phone.
- [x] Export scope and quality labels wrap as whole controls, never as vertical
      letter streams.
- [x] A lasso selection exposes Beautify, recolor, delete, and dismiss without a
      render overflow on a 360dp phone.
- [x] Text-object actions and resize handles remain approximately 44 logical
      pixels on screen when the page is scaled below 100%.
- [x] On narrow phones, a complete Fit Width page keeps the same scale and
      document coordinates as the tablet layout while using a small top inset
      instead of vertical centering that creates two large blank bands.
- [x] Empty folder/notebook names cannot be submitted.
- [x] Folder/notebook permanent-delete confirmation uses danger emphasis.
- [x] The eraser removes ink locally, removes a touched shape/image atomically,
      and records the complete action for undo/redo.
- [x] Pen, Highlighter, and Shape are peer-level toolbar entries; selecting
      Shape keeps its explicit `Shape · <type>` properties entry visible.
- [x] Shape properties expose both preset geometry and an explicit Auto shape
      mode for one-stroke local recognition.
- [x] Entering Shape gives the properties entry a short, non-blocking pulse and
      an accessibility hint instead of opening a modal automatically.
- [x] Existing notebook data and wider layouts remain compatible.

## Alternatives And Tradeoffs

- Replace narrow bookshelf spines with a phone card grid: implemented as an
  experiment, then rolled back after user review because it weakened InkNest's
  intended bookshelf identity.
- Horizontally scroll every overflowing toolbar: reliable as a fallback, but it
  hides actions. The lasso bar instead groups phone recoloring into one palette
  action.

## Dependencies And Risks

- Product or technical dependency: responsive Flutter layout and the existing
  notebook/folder action callbacks.
- Data, privacy, performance, or migration risk: none; this is presentation and
  interaction only.
- Regression risk: width breakpoints could affect split view, so tests pin both
  360dp phone and 600dp bookshelf behavior.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/android-phone-ux-polish/UI_UX_SPEC.md`
- Implementation status: Delivered
- Verification: `flutter analyze`; focused library/editor widget tests; all 293
  Flutter tests; physical-device hot reload. No new screenshot validation was
  requested for the bookshelf restoration.
