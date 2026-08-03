# Editor Workspace V2 Product Brief

- Status: Delivered
- Size: Medium
- Updated: 2026-08-03
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` — Editor UI

## Problem

The current editor preserves page coordinates and keeps every feature reachable,
but its command hierarchy still makes routine writing feel heavier than it
should on iPad.

- The header presents the page navigator after the title and beside document
  actions, so location and actions do not follow a natural left-to-right order.
- Undo and redo sit inside the tool dock even though they affect page content,
  interrupting the relationship between a tool and its properties.
- Four fixed presets remain permanently visible at wide widths and visually
  compete with the active tool.
- Pen and Highlighter are merged into one button. Switching between two of the
  most frequent study tools therefore requires opening properties instead of a
  direct one-tap change.
- The two stacked chrome rows have almost equal visual weight, making notebook
  context, editing tools, and secondary actions look like one long control bar.

The target user is an iPad note taker who repeatedly alternates between pen,
highlighter, eraser, selection, and undo while reading or writing. The desired
outcome is a workspace whose hierarchy is understandable before the user learns
the icon order.

## Recommended Outcome

Adopt a calmer two-level editor command model:

1. The **document bar** owns location and page-level actions: Back, notebook
   title/page position, Pages controls, Undo, Redo, Search, and More.
2. The **contextual tool dock** owns only editing mode: Pen, Highlighter,
   Eraser, Lasso, Insert, active tool style, and Finger input mode.
3. Pen and Highlighter are separate one-tap tools and remember independent
   settings.
4. Fixed presets remain available inside tool properties, but no longer occupy
   the persistent dock.
5. Tapping an already-selected configurable tool opens its properties, while
   the visible style control remains the explicit alternative.
6. Time-sensitive document actions adapt to available width: Record appears at
   720px and above, Export appears at 1000px and above, and both remain in a
   labelled More menu for compact layouts and discoverability.
7. Page work uses one coherent system: a compact header pager owns Previous,
   Pages, Next, and Add; Outline and Bookmarks are separate header entries with
   focused panels; the Pages panel owns thumbnail management without mixing in
   outline, bookmark, or current-page template configuration.
8. Every manual blank-page insertion first asks for a paper style, then creates
   the page only after selection. Cancelling the picker creates nothing.

This keeps all existing features and page-coordinate behavior intact while
shortening the highest-frequency tool paths and restoring a clear information
hierarchy.

## Scope

- In scope:
  - Reorder the document bar around Back → notebook context → Pages controls →
    history → Search → More.
  - Move Undo and Redo from the tool dock into the document bar.
  - Expose Pen and Highlighter as separate primary tools.
  - Remove persistent preset buttons and the preset overflow from the dock.
  - Keep presets and all manual color/width/style controls in the properties
    popover or compact sheet.
  - Open contextual properties when an already-selected Pen, Highlighter, or
    Eraser control is tapped; Shape remains configurable from the visible style
    control after Insert → Shape.
  - Preserve current iPad width breakpoints, minimum targets, canvas transforms,
    page navigation, search, audio, import, export, and write-protection rules.
  - Group More actions under Document, Audio, and View headings instead of
    relying on unlabelled dividers; page commands belong to the pager and Pages.
  - Show a direct Record control at ≥720px and a direct Export control at
    ≥1000px; preserve their More-menu entries at every width.
  - Replace the page-count badge with Previous / page position / Next / Add
    controls, with disabled edge states and explicit semantics.
  - Make quick Add ask for a paper style, insert after the current page, and
    navigate to the new page.
  - Move the Pages-tab Add control to a fixed toolbar instead of the end of the
    thumbnail grid, retaining current-page Rotate while moving Bookmarks to its
    own focused panel and removing current-page Template.
  - Expose Outline and Bookmarks as separate top-bar entry points, each opening
    its own focused panel instead of tabs in the Pages navigator.
  - Apply paper-style selection to toolbar Add, Pages-panel Add, and advanced
    blank-page insertion commands.
  - Remove the Page section from More; retain advanced per-page insertion,
    duplication, deletion, movement, and rotation in thumbnail action menus.
- Non-goals:
  - New drawing engines, tools, content types, persisted preset customization,
    or a unified undo model.
  - Changes to page coordinates, storage models, legacy conversion, sync,
    phone, or Web behavior.
  - Replacing the existing viewport or page navigator.

## User Flow

1. Open a notebook and read its title/page position beside the Pages entry.
2. Write with Pen, or switch directly to Highlighter, Eraser, or Lasso in one
   tap.
3. Tap the selected configurable tool or the style preview to adjust it; choose
   a preset or manual color/width in the existing contextual panel.
4. Undo or redo from the document bar without crossing the tool/property
   cluster.
5. Use Insert for Text, Image, or Shape; use Finger for touch behavior; use
   Search or More for lower-frequency notebook commands.
6. Dismiss a popover or cancelled picker with no change to page position,
   selected tool, or saved content.

## Acceptance Criteria

- [x] Back, notebook context, Pages controls, Undo, Redo, Search, and More appear in that
  hierarchy without overflow at 600, 834, and 1194 logical pixels.
- [x] Pen and Highlighter are both one-tap primary tools and retain independent
  remembered settings.
- [x] Persistent preset buttons and preset menus are absent from the dock;
  presets remain reachable in tool properties.
- [x] Undo and Redo remain accurately labelled as ink-only history and retain
  existing enabled/disabled behavior.
- [x] Tapping an active configurable tool opens its contextual properties;
  tapping an inactive tool selects it without unexpectedly opening a panel.
- [x] Insert, Finger modes, selection actions, audio, search, PDF, page, zoom,
  and export workflows remain reachable.
- [x] Existing notebooks and page coordinates are unchanged.
- [x] Important controls retain tooltips, selected semantics, and at least 44px
  targets at supported iPad and Split View widths.
- [x] Record is directly reachable at ≥720px, Export is directly reachable at
  ≥1000px, and neither crowds the 600px Split View document bar.
- [x] More groups non-page actions under Document, Audio, or View while
  disabled/busy states remain visible and understandable.
- [x] Previous and Next switch adjacent pages directly, expose disabled first/
  last states, and preserve the current page's session viewport.
- [x] Pages, Outline, and Bookmarks have separate top-bar entry points and open
  focused panels without a shared tab bar.
- [x] Every manual blank-page insertion asks for a paper style first; cancelling
  creates no page, while selection inserts and navigates to the new page.
- [x] Pages centralizes thumbnails and page operations without current-page
  Template or Bookmark controls; Bookmark management lives in Bookmarks.

## Alternatives And Tradeoffs

- Keep Pen and Highlighter merged: saves one icon, but adds friction to a very
  frequent study workflow. Rejected.
- Keep presets visible on wide layouts: allows one-tap style changes, but makes
  the default hierarchy depend on memorized colored dots and overwhelms the
  primary tools. Presets remain one tap behind the style control.
- Move the tool dock onto the canvas as a floating palette: visually lighter,
  but risks covering handwriting and adds drag/persistence behavior. Deferred
  until the simpler hierarchy is validated on a real iPad.

## Dependencies And Risks

- `EditorToolbar` currently owns remembered tool settings and preset matching;
  restructuring must preserve those values when Pen and Highlighter split.
- Moving history controls changes widget-test entry points but not history
  semantics or stored data.
- Compact widths must be tested for overflow because the document bar gains
  Undo and Redo while retaining 44px targets.

## Open Decisions

- None for this delivery. A later real-device study can decide whether a
  movable floating palette adds value beyond this hierarchy.

## Delivery

- UI/UX spec:
  `docs/product/features/editor-workspace-v2/UI_UX_SPEC.md`
- Implementation status: Delivered on 2026-08-03
- Verification: Focused responsive/tool/page-navigation tests and the full 133-test Flutter
  suite pass; `flutter analyze` and `git diff --check` pass. Responsive coverage
  confirms compact, regular, and wide direct-action visibility, independent
  Pages/Outline/Bookmarks panels, paper-style-first insertion and cancellation,
  persistent regular-width management, and labelled More sections. Real-iPad
  Pencil, rotation, and Split View QA remains a release follow-up.
