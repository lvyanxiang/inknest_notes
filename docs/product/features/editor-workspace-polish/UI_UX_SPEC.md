# Editor Workspace Interaction Polish UI/UX Specification

- Status: Delivered
- Updated: 2026-07-27
- Product brief:
  `docs/product/features/editor-workspace-polish/PRODUCT_BRIEF.md`
- Affected surfaces: Notebook editor header, tool dock, page viewport chrome,
  zoom/fit feedback, Finger mode presentation, workspace colors

## Recommendation

Keep the redesigned writing-first shell, but remove redundant paper overlays and
make tool / touch / zoom state readable at a glance.

Lead design:

1. Header owns page navigation; no bottom floating page chip.
2. Zoom chrome collapses to a quiet Fit-Width-relative chip; expands on demand
   and shows a transient center badge while zooming.
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

1. Enter the editor from the library. Paper is clear except for a quiet zoom
   chip in the top-right when needed.
2. Tap a primary tool or the properties chip. On ≥720 width, properties open as
   an anchored popover under the dock; outside tap or Close dismisses it.
3. Pinch or expand the zoom chip and change scale. A center badge shows the
   Fit-Width-relative percentage, then fades after idle.
4. Choose Fit Width / Fit Page from the expanded zoom menu or More → View.
5. Open Finger mode. Finger writes remains the quiet default; choosing Finger
   moves emphasizes the mode until the user returns to Finger writes.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Idle writing | Quiet zoom chip; no bottom page chip | Write with current tool; open Pages from header | Paper remains primary |
| Zoom active | Expanded zoom controls + center % badge | Zoom in/out, Fit Width, Fit Page | Badge uses Fit-Width-relative %; collapses after idle |
| Properties open (≥720) | Anchored popover near dock | Change color/width/preset/shape | Outside tap or Close dismisses; tool stays active |
| Properties open (<720) | Bottom sheet | Same property actions | Drag handle / Close / outside dismiss |
| Finger writes | Quiet mode chip labelled Finger writes | Open menu; enable/disable Writing assist | Not strongly selected |
| Finger moves | Strong selected mode chip | Pan with finger; Pencil still writes | Strong fill + outline + semantics |
| More → View | Fit Width / Fit Page rows | Apply to current viewport | Menu closes; viewport updates |

## Layout And Components

- Remove `_PagePositionButton` from the canvas overlay.
- Keep header Pages control; show current page context in the header subtitle /
  badge already present.
- Zoom chip:
  - Collapsed: compact `%` control, opaque chrome surface, 44px min height.
  - Expanded: Zoom out, Fit menu / %, Zoom in.
  - Transient badge: centered, non-interactive, ~800–1800ms after last zoom
    change.
  - Percentage copy: `round(effectiveScale / fitWidthScale × 100)%`.
- More menu adds a View section before or after existing groups:
  - Fit width
  - Fit page
- Tool properties popover width ~360px, chrome surface `#FFFCF7`, 12px radius.
- Finger mode: only Finger moves uses the selected dock treatment by default
  styling rules.
- Workspace `#F3F0E8`, chrome `#FFFCF7`, selected fill `#DCEEEE`, ink `#1E2526`,
  divider/paper border `#DDD7CB`, primary `#2F6F73`.

### User-facing copy

- `Fit width`
- `Fit page`
- `Finger writes`
- `Finger moves`
- `Writing assist`
- `Zoom and fit`
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

- Icon-only zoom and Pages controls keep unique tooltips and semantics.
- Expanded zoom controls remain ≥44×44.
- Selected tool and Finger moves use fill + outline + semantics, not color
  alone.
- Fit Width / Fit Page remain available without relying on pinch.

## UI Acceptance Criteria

- [x] No bottom floating page chip covers the paper.
- [x] Idle zoom chrome is collapsed; zoom and fit remain reachable.
- [x] Zoom badge percentage is Fit-Width-relative and temporary.
- [x] More → View Fit actions work on the current page.
- [x] Properties use popover ≥720 and sheet <720.
- [x] Finger writes is quiet; Finger moves is strongly selected.
- [x] Existing editor workflows remain reachable.

## Verification

- Widget tests: toolbar properties presentation, finger-mode emphasis, workspace
  zoom/fit menu and More → View.
- Responsive checks at 600×800, 834×1194, 1194×834.
- Manual iPad check later for Pencil palm rejection remains separate.

## Implementation Review

- Status: Delivered
- Intentional deviations: none
