# Editor Workspace Interaction Polish Product Brief

- Status: Delivered
- Size: Medium
- Updated: 2026-07-27
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md` — Editor UI

## Problem

The editor workspace redesign fixed structure and coordinate reliability, but
high-frequency interaction still feels uncomfortable:

- A floating page chip covers the bottom of the paper even though the header
  already opens Pages.
- Permanent zoom chrome covers the top-right writing area, and the percentage
  does not read relative to Fit Width.
- Tool properties open as a bottom sheet on iPad, which covers the page instead
  of staying near the tool dock.
- Finger mode looks permanently selected, so the default writing state and the
  active “Finger moves” state are hard to tell apart.
- Fit Width and Fit Page are only discoverable inside the on-canvas zoom menu.

The target user is an iPad note taker who wants the paper clear while writing
and wants tool, touch, and zoom state to be obvious without hunting.

## Recommended Outcome

Deliver a writing-first interaction polish pass:

1. Remove the redundant bottom page chip; keep page navigation in the header.
2. Collapse on-canvas zoom chrome by default, show a transient Fit-Width-relative
   zoom badge during zoom, and expose Fit Width / Fit Page from More → View.
3. Open tool properties as an anchored popover on regular/wide widths; keep a
   bottom sheet only for compact Split View.
4. Treat Finger writes as the quiet default and Finger moves as the emphasized
   active mode.
5. Align workspace chrome colors with the editor redesign tokens so selected
   controls read clearly against the paper.

## Scope

- In scope:
  - Editor header page affordance clarity.
  - Canvas chrome that covers the paper during writing.
  - Zoom status feedback and Fit Width / Fit Page discoverability.
  - Tool property presentation and selected-state clarity in the tool dock.
  - Finger mode visual hierarchy.
  - Editor workspace color tokens used by chrome and selection.
- Non-goals:
  - Latency / jank performance work.
  - Coordinate-system changes or legacy conversion.
  - New drawing tools, recognition, sync, phone, or Web editor work.
  - Full toolbar customization or persistent presets.
  - Unified undo history beyond draw/erase.

## User Flow

1. Open a notebook and start writing with the paper mostly clear of floating
   chrome.
2. Switch tools or open properties from the dock; properties appear near the
   dock on iPad and do not cover the whole page.
3. Pinch or tap zoom controls; a Fit-Width-relative percentage appears briefly,
   then leaves the writing area.
4. Choose Fit Width or Fit Page from the zoom chip menu or More → View.
5. Switch Finger writes / Finger moves; only the non-default moves mode looks
   strongly selected.

## Acceptance Criteria

- [x] The floating bottom page chip is gone; Pages remains reachable from the
  header at compact, standard, and wide widths.
- [x] On-canvas zoom chrome does not stay fully expanded while idle; users can
  still zoom in, zoom out, Fit Width, and Fit Page.
- [x] Zoom percentage is shown relative to Fit Width (`effective / fitWidth ×
  100`) during active zoom and dismisses after a short idle period.
- [x] More → View includes Fit Width and Fit Page and applies them to the
  current page viewport.
- [x] Tool properties open as an anchored popover at ≥720 logical width and as a
  bottom sheet below that.
- [x] Finger writes is visually quiet by default; Finger moves uses the strong
  selected treatment.
- [x] Existing drawing, page navigation, insert, lasso, audio, search, and
  export flows remain available.
- [x] Focused widget and workspace tests cover the changed controls.

## Alternatives And Tradeoffs

- **Keep permanent zoom bar and only restyle it:** lower effort, but still
  covers the writing corner every session. Rejected for this polish pass.
- **Move all zoom into the header only:** clears the paper completely, but makes
  pinch-follow-up controls farther from the gesture. Keep a collapsible
  on-canvas chip plus More → View.
- **Always use bottom sheets for properties:** consistent with phone patterns,
  but poor for iPad writing. Keep sheets only for compact widths.

## Dependencies And Risks

- Zoom and fit state lives inside the page viewport widget; Fit actions from
  More need a stable way to reach the active viewport.
- Widget tests currently assume always-visible zoom tooltips; expand-on-demand
  chrome must keep those actions reachable in tests.
- Do not change persisted page coordinates or coordinate versions.

## Open Decisions

- None for this delivery. Real-device Pencil QA remains a separate follow-up from
  the workspace redesign.

## Delivery

- UI/UX spec:
  `docs/product/features/editor-workspace-polish/UI_UX_SPEC.md`
- Implementation status: Delivered on 2026-07-27
- Verification: Focused editor toolbar, workspace, viewport model, and full
  `flutter test` / `flutter analyze` results recorded in
  `docs/development/STATUS.md`.
