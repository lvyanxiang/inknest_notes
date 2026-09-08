# Editor Workspace Interaction Polish UI/UX Specification

- Status: Delivered
- Updated: 2026-09-08
- Product brief:
  `docs/product/features/editor-workspace-polish/PRODUCT_BRIEF.md`
- Affected surfaces: Notebook editor header, tool dock, page viewport chrome,
  zoom/fit feedback, Finger mode presentation, workspace colors

## Recommendation

Keep the redesigned writing-first shell, but remove redundant paper overlays and
make tool / touch / zoom state readable at a glance.

Lead design:

1. One icon-only Pages header action owns page navigation; no visible notebook
   title/page subtitle or bottom floating page chip.
2. Paged paper has no persistent zoom chrome. Pinch and More → View own
   incremental zoom; a direct header action restores Fit Width, with a
   transient center badge as feedback.
3. Tool properties stay near the dock as a popover on regular/wide widths.
4. Finger writes is the quiet default; Finger moves is the strong mode chip.
5. Reuse editor redesign tokens for workspace, chrome, selected fill, and paper.
6. Pen and Highlighter share one primary writing control; style switches live in
   properties/presets. Selected dock controls use a soft fill and primary icon
   tint without a heavy outline border.
7. Tool properties use a compact card: stroke preview header, segmented Style,
   icon presets, circular color swatches, and visual width tiles — not a long
   labelled form.
8. Editor popovers/menus/sheets share `EditorChrome` surfaces (`#FFFCF7`,
   12px radius, divider border): Insert and Finger use anchored cards; More /
   zoom / page actions use chrome-tinted menus; template, search, and audio use
   chrome sheets; Export / Smart Ink / delete confirmations use chrome dialogs.
9. Header and tool dock share one chrome surface: AppBar hosts the dock as
   `bottom`, Pages badge uses primary teal (not error red), property chip uses
   a short `Color · width` label. On tablet widths the dock controls form one
   centered cluster (tools → properties/presets → undo/redo → Finger) instead
   of stretching Finger to the trailing edge and leaving a middle dead zone.

## User Flow

1. Enter the editor from the library. Paper is clear of persistent zoom
   controls.
2. Tap a primary tool or the properties chip. On ≥720 width, properties open as
   an anchored popover under the dock; outside tap or Close dismisses it.
3. Pinch the paper to change scale. A center badge shows the
   Fit-Width-relative percentage, then fades after idle.
4. Choose Zoom out or Zoom in from More → View when an explicit incremental
   control is needed. Tap the header Fit Width icon to restore the default
   reading scale.
5. Open Finger mode. Finger writes remains the quiet default; choosing Finger
   moves emphasizes the mode until the user returns to Finger writes.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Idle writing | No on-paper zoom or page chip | Write with current tool; open Pages from header | Paper remains primary |
| Zoom active | Center % badge only | Continue pinch gesture or use More → View | Badge uses Fit-Width-relative % and fades after idle |
| Properties open (≥720) | Anchored popover near dock | Change color/width/preset/shape | Outside tap or Close dismisses; tool stays active |
| Properties open (<720) | Bottom sheet | Same property actions | Drag handle / Close / outside dismiss |
| Finger writes | Quiet mode chip labelled Finger writes | Open menu; enable/disable Writing assist | Not strongly selected |
| Finger moves | Strong selected mode chip | Pan with finger; Pencil still writes | Strong fill + outline + semantics |
| More → View | Zoom out / Zoom in rows | Apply to current viewport | Menu closes; viewport updates and briefly confirms scale |
| Header Fit Width | Compact Fit Width icon before More | Reset current viewport | View returns to Fit Width and briefly confirms 100% |

## Layout And Components

- Remove `_PagePositionButton` from the canvas overlay.
- Keep one 20dp `layers_outlined` Pages icon in a 44dp header target. Its
  tooltip/semantic label includes the current page and total. Place it first in
  the right-aligned document action group rather than as a separate left title.
- Remove rotation from the Pages header and thumbnail action menu. Keep
  rendering compatibility for notebooks that already contain rotated pages.
- Do not render a persistent zoom chip or bar over paged paper.
- Zoom feedback uses a centered, non-interactive badge for ~800–1800ms after
  the last zoom or Fit action.
- Percentage copy: `round(effectiveScale / fitWidthScale × 100)%`.
- More menu includes one View section:
  - Zoom out
  - Zoom in
- Header keeps a direct Fit Width icon immediately before More.
- Header action icons use 20dp visuals inside 44dp touch targets, reducing
  apparent size and spacing without weakening touch reliability.
- Tool properties popover width ~360px, chrome surface `#FFFCF7`, 12px radius.
- Finger mode: only Finger moves uses the selected dock treatment by default
  styling rules.
- Workspace `#F3F0E8`, chrome `#FFFCF7`, selected fill `#DCEEEE`, ink `#1E2526`,
  divider/paper border `#DDD7CB`, primary `#2F6F73`.

### User-facing copy

- `Fit width`
- `Finger writes`
- `Finger moves`
- `Writing assist`
- `Close tool properties`

## Input And Responsive Behavior

- Pencil writing remains uninterrupted; overlays do not capture stroke input
  except their own hit targets.
- Pinch zoom continues to own two-finger gestures.
- Regular/wide (≥720): properties popover.
- Compact (<720): properties bottom sheet.
- Portrait, landscape, and Split View keep the same width-driven rules.
- Phone/Web remain out of scope.

## Accessibility

- Pages controls keep unique tooltips and semantics.
- More → View provides labelled zoom actions with 44px menu rows.
- The direct Fit Width icon has a `Fit width` tooltip/semantic label and a 44dp
  touch target.
- Selected tool and Finger moves use fill + outline + semantics, not color
  alone.
- Fit Width remains available without relying on pinch.

## UI Acceptance Criteria

- [x] No bottom floating page chip covers the paper.
- [x] The header uses one icon-only Pages action with no visible title/subtitle.
- [x] Pages and thumbnail menus expose no rotation action.
- [x] Paged paper has no persistent zoom chrome; Zoom out and Zoom in remain
      reachable from More → View, and one Fit Width reset remains directly
      reachable from the header.
- [x] Zoom badge percentage is Fit-Width-relative and temporary.
- [x] The direct header Fit Width action resets the current page reliably.
- [x] Properties use popover ≥720 and sheet <720.
- [x] Finger writes is quiet; Finger moves is strongly selected.
- [x] Existing editor workflows remain reachable.

## Verification

- Widget tests: toolbar properties presentation, finger-mode emphasis, direct
  Fit Width action, and More → View zoom actions.
- Responsive checks at 600×800, 834×1194, 1194×834.
- Manual iPad check later for Pencil palm rejection remains separate.

## Implementation Review

- Status: Delivered
- Intentional deviation recorded 2026-09-08: the collapsed on-canvas zoom chip
  was removed after continuous-page use showed that it still obscured paper.
