# Editor Workspace and Stable Page Viewport UI/UX Specification

- Status: Core implementation delivered; legacy conversion and release QA remain
- Updated: 2026-07-27
- Product brief:
  `docs/product/features/editor-workspace-redesign/PRODUCT_BRIEF.md`
- Affected surfaces: Notebook editor header, tool controls, page viewport,
  zoom/pan behavior, page navigation, audio status, tool context actions, and
  responsive iPad layouts

## Recommendation

Use a quiet, writing-first workspace built from three visually distinct layers:

1. A **document header** for leaving the notebook, identifying the current
   notebook/page, undo/redo, search, recording, sharing, and grouped document
   commands.
2. A **contextual tool dock** for frequent editing tools and only the selected
   tool's properties.
3. A **stable page viewport** whose paper has fixed document dimensions while
   the surrounding viewport handles window size, page rotation, zoom, and pan.

The page navigator becomes an on-demand left panel instead of a permanent
bottom strip. The same width-driven shell works in portrait, landscape, Split
View, and resizable windows; the paper never changes its intrinsic dimensions
because the device rotates.

This recommendation keeps handwriting dominant, removes duplicated controls,
and corrects the current mismatch between screen-fitted pointer coordinates and
persisted page coordinates before visual polish.

Current official patterns support the direction without requiring InkNest to
copy another product:

- [Goodnotes toolbar customization](https://support.goodnotes.com/hc/en-us/articles/8900755183631-Customize-the-toolbar)
  groups hidden tools in overflow and lets users prioritize writing tools.
- [Notability Toolbox customization](https://support.gingerlabs.com/hc/en-us/articles/6272405402650-Customize-your-Toolbox)
  treats duplicated pen-like tools as complete style presets.
- [Goodnotes document sidebar](https://support.goodnotes.com/hc/en-us/articles/9497798035983-Use-the-Sidebar-to-navigate-your-document)
  centralizes Pages, Outlines, bookmarks, and page actions.
- [Goodnotes zoom and scroll](https://support.goodnotes.com/hc/en-us/articles/6554036735631-How-to-zoom-and-scroll-through-pages)
  keeps zoom/pan as view behavior rather than changing paper geometry.
- Apple's [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
  and [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
  guidance informs the width-driven layout and grouped action hierarchy.

## User Goal And Entry Point

The user enters from a notebook on the library shelf and wants to:

- recognize the current tool and touch behavior immediately;
- write with Pencil or finger without first configuring the page;
- switch common tools or a complete preset in one tap;
- find insert, page, PDF, search, audio, and export actions by category;
- navigate pages without permanently sacrificing writing height; and
- rotate or resize the device without changing content placement or losing the
  current writing location.

## Information Architecture

### Document header

Always-visible priority:

1. Back.
2. A navigator button displayed as a pages icon plus `n / total`; its semantic
   label is `Pages, page n of total`.
3. A separate, non-interactive notebook title that truncates before actions.
4. Undo ink stroke and redo ink stroke.
5. Search.
6. More.

Regular/wide layouts may additionally show Record and Share directly. Compact
layouts move inactive Record and Share commands into More; an active recording
always remains visible as a red status control.

The More menu uses labelled sections:

- **Page:** Template, Bookmark/Remove bookmark, Rotate clockwise.
- **Notebook:** Import PDFs, Export PDF.
- **Audio:** Start recording or Audio recordings.
- **View:** Fit Width, Fit Page, Zoom In, Zoom Out.

Disabled menu rows remain visible when the reason teaches the rule, such as
`Template unavailable on PDF pages`; otherwise unavailable actions are omitted
from unrelated states.

### Contextual tool dock

Primary tools remain one tap away:

- Pen
- Highlighter
- Eraser
- Lasso
- Insert

Insert opens a labelled popover with Text, Image, and Shape. After the user
chooses Text or Shape, that tool stays active until another primary tool is
chosen. Image returns to the previous writing tool after a successful or
cancelled picker.

The active-property area changes by context:

| Active context | Property control |
|---|---|
| Pen / Highlighter | Complete preset preview, color, width, and style popover |
| Eraser | Eraser mode and size |
| Lasso, no selection | Ink-only selection usage hint |
| Lasso, selection | Move/resize remains direct; show Recolor, Smart Ink, Delete, Clear |
| Text | Text style, size, color, and handwriting-style toggle |
| Shape | Shape type, stroke color, and width |
| Image placement | Done/Cancel and existing move/resize/delete controls |

The current four favorites become complete preset slots inside the tool dock.
On wide layouts up to four slots may be visible. Compact layouts show the active
preset and a Presets button; all slots remain available in the property
popover. The old floating favorites toolbar is removed.

The first delivery uses four fixed slots: Black Pen 3pt, Teal Pen 5pt, Red Pen
5pt, and Yellow Highlighter 12pt. A new editor session starts with Black Pen
3pt. Manual color, width, or style changes create a visibly labelled Custom
configuration for that tool and never overwrite a fixed slot. Pen,
Highlighter, Eraser, and Shape remember their last Custom values for the current
editor session only.

Finger behavior is a separate, labelled mode rather than a competing primary
tool:

- `Finger writes` preserves the current default and applies Finger Writing
  Assist after a completed touch stroke.
- `Finger moves` lets one finger pan while Pencil/stylus continues to use the
  selected editing tool.

The mode control must show text on regular widths or a unique semantic label and
state on compact widths. `Finger assist` moves into the `Finger writes`
settings instead of occupying a permanent icon.

Entering Lasso temporarily suspends Finger moves so Pencil or one finger can
define an ink selection. Leaving Lasso restores the prior finger mode. While a
selection is active, changing finger mode is blocked until the selection is
cleared.

### Notebook navigator

The header's `Page n of total`/navigator control opens one component with:

- Pages
- Outline
- Bookmarks

Pages reuses the current thumbnail previews, selection state, bookmarks, add
page, and per-page action menu. Existing insert, duplicate, delete, move, and
rotate behavior remains available. Page actions stay reachable without relying
on long press.

On wide windows the navigator can be pinned to the left and remembers that
choice for the current editor session. It starts collapsed on first entry so
writing space remains primary. On standard and compact windows it overlays the
canvas, closes after page selection by default, and can be dismissed with
outside tap, Escape, or its close button.

An overlay navigator is modal to the canvas: it blocks canvas pointer events,
traps keyboard focus inside the panel, and returns focus to the navigator button
when closed. A pinned navigator is non-modal.

Navigator empty and destructive states are explicit:

- Outline: `No outline in this notebook`.
- Bookmarks: `No bookmarked pages`.
- The last remaining page cannot be deleted and explains
  `A notebook needs one page`.
- Deleting any other page requires confirmation because page deletion is not
  covered by the first undo history. After deleting the current page, select
  the nearest remaining page.

## Layout And Components

### Wide layout

Applies at a usable window width of at least 1100 logical pixels.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ ‹  Pages  Notebook 1 · 1/24      Undo Redo     Record Search Share      More │
├───────────────┬──────────────────────────────────────────────────────────────┤
│ Pages         │ Pen Highlighter Eraser Lasso Insert │ Presets │ Finger moves│
│ Outline       ├──────────────────────────────────────────────────────────────┤
│ Bookmarks     │                                                              │
│               │                    fixed paper                               │
│ thumbnails    │              (viewport may zoom and pan)                     │
│               │                                                              │
│ + Add page    │                                                              │
└───────────────┴──────────────────────────────────────────────────────────────┘
```

- Header height: 52–56px.
- Tool dock height: 56px.
- Pinned navigator width: 248–280px.
- The navigator can collapse entirely; the header page control remains.
- Canvas outer padding: 24px minimum, 32px where space permits.

### Standard portrait / compact landscape

Applies from 720 through 1099 logical pixels.

```text
┌──────────────────────────────────────────────────────────────┐
│ ‹  1/24  Notebook 1                 Undo Redo Search     More │
├──────────────────────────────────────────────────────────────┤
│ Pen Highlighter Eraser Lasso Insert │ Preset │ Touch mode    │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                       fixed paper                            │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Pages / Outline / Bookmarks open as a left overlay panel.
```

- Inactive Record and Share move to More.
- Tool labels may collapse to icons, but no primary control requires horizontal
  scrolling.
- The navigator overlays at 320px or up to 80% of window width.
- No permanent bottom thumbnail strip remains.

### Narrow Split View

Applies below 720 logical pixels.

- Keep one 52–56px header row with Back, page count, truncated title, Undo,
  Redo, and More. Search remains visible when space permits; otherwise it is the
  first More item.
- Keep core tools, Insert, one property button, and touch mode in a 56px icon
  dock. Presets and detailed properties live in popovers.
- Open the notebook navigator as a full-height modal panel.
- Never shrink targets below 44px and never hide a primary tool behind
  unindicated horizontal scrolling.

Breakpoints are based on actual window width, not a binary portrait/landscape
flag, so iPad Split View and freeform resizing use the same rules.

### Visual treatment

- Define editor theme roles from the current Material 3 direction:
  - workspace `#F3F0E8`;
  - chrome surface `#FFFCF7`;
  - paper `#FFFFFF`;
  - primary/active teal `#2F6F73`;
  - selected control surface `#DCEEEE`;
  - primary ink `#1E2526`;
  - divider and paper border `#DDD7CB`;
  - error roles from the app `ColorScheme`.
- Use 17px/600 for the notebook title, 12px/600 for page and tool labels,
  16px/700 for popover titles, and 14px/400 for popover body copy.
- Keep paper white with a subtle neutral border and low, broad shadow.
- Use a 1px paper border and a `#1A1E2526` shadow with 20px blur and 8px
  vertical offset.
- Use opaque control surfaces near the page; do not place translucent controls
  over precision writing areas.
- Inactive icon buttons use a quiet transparent or surface treatment. Only the
  selected tool, active mode, active recording, and destructive state receive
  strong color.
- Use 12px dock/popover radius, 8px small-control radius, and the existing
  theme's 4/8/12/16/24 spacing rhythm.
- Selected state combines fill, outline/indicator, and semantics; color alone is
  insufficient.
- The property/preset preview combines a tool glyph, named color swatch, and
  visible stroke thickness.

### Reused components

- Current `ColorScheme`, typography, sheets, dialogs, snackbars, and safe-area
  behavior.
- Existing page thumbnail painter and PDF background preview.
- Existing page action menu behavior.
- Existing lasso selection outline and upright selection action pattern.
- Existing audio recording/playback functionality.
- Existing page-template, search, image, text, shape, and drawing layers after
  they share a canonical transform.

### New or extracted components

- `EditorWorkspaceShell`
- `EditorDocumentHeader`
- `EditorToolDock`
- `EditorToolPropertiesPopover`
- `EditorPresetButton`
- `NotebookNavigator`
- `PageViewportController` and a testable `PageViewportTransform`
- An editor-specific theme extension for target size, spacing, control
  surfaces, selected state, border, and paper shadow

## Stable Page Viewport

### Coordinate contract

Use three explicit, top-left-origin spaces whose positive x axis points right
and positive y axis points down:

- **Document space (D):** unrotated `0…W × 0…H`, where
  `W = page.width` and `H = page.height`. All saved strokes, text, images,
  shapes, templates, selections, and search regions use this space.
- **Rotated page space (R):** the normalized, non-negative visual bounding box
  after the persisted clockwise `rotationQuarterTurns` value `q`.
- **Viewport space (V):** logical pixels in the entire editor viewport,
  including the coordinate origin above/left of any usable content insets.

The canonical D→R mapping is:

- q0: `(x, y)`
- q1: `(H - y, x)`
- q2: `(W - x, H - y)`
- q3: `(y, W - x)`

R has size `W × H` for q0/q2 and `H × W` for q1/q3. This mapping includes the
translation needed to keep clockwise rotations out of negative coordinates.

Let `U` be the usable canvas rectangle inside V, `o` the rotated page origin
relative to `U.topLeft`, and `s` the effective scale in logical viewport pixels
per document unit.
Then `r = rotateAndNormalize(d, q)` and:

`v = U.topLeft + o + s × r`

The same utility provides the exact inverse `viewportToDocument`. PDF export
does not reuse the viewport scale or origin; it shares only the canonical D
coordinates and q rotation semantics.

Separate two rendering/interaction layers:

- **Document content layer:** fixed `W × H` content for PDF, template, ink,
  text-box body, image, shape, and search highlight. It uses D→R→V together.
- **Viewport operation layer:** lasso-selection, image-resize, and text-box
  resize handles, hit regions, and action bars project document anchors into V
  but remain upright and at least 44px regardless of page rotation or zoom.

Content creation, object hit testing, and object editing first convert V→D and
reject points outside D. Their drag deltas use the inverse transform's linear
rotation/scale component, and screen-space hit tolerance converts to document
units. Viewport pan deltas and pinch distances remain in V; only the pinch/pan
focal point converts through V→D to preserve its document anchor. Individual
content widgets must not persist raw `localPosition` or raw screen `delta`.

The editor-level viewport controller, not a keyed page widget, owns:

- `Map<pageId, {mode, focusDocumentPoint, customScale}>`;
- mode `fitWidth`, `fitPage`, or `custom`;
- an absolute `customScale` only for Custom mode; and
- the document point used to derive the page origin.

### Fit and zoom behavior

- `U` subtracts safe areas, the document header, tool dock, a pinned navigator,
  and non-overlay recording/playback or text-keyboard space. Overlay navigator
  panels and popovers do not change `U`.
- Use 24px page padding:
  - `fitWidthScale = (U.width - 48) / R.width`;
  - `fitPageScale = min((U.width - 48) / R.width,
    (U.height - 48) / R.height)`.
- First visit to a page: Fit Width, horizontally centered, with the rotated page
  top at `U.top + 24` when the page is taller than U.
- Fit Width and Fit Page derive scale from the current R size and U; neither
  stores an absolute scale.
- Fit modes are provisional. The first pan, pinch, allowed zoom double tap,
  Zoom In/Out command, or content gesture enters Custom at the current
  effective scale.
- Custom preserves its absolute effective scale and the document point at the
  usable-canvas center across resize/orientation changes. Clamp Custom between
  `0.5 × fitPageScale` and `8 × fitWidthScale`; resize changes scale only if the
  preserved value falls outside these bounds.
- Zoom In multiplies Custom scale by 1.25 and Zoom Out by 0.8 around the usable
  canvas center. A one-finger double tap toggles between Fit Width and
  `2 × fitWidthScale` Custom zoom around the tapped document point only while
  `Finger moves` is active. `Finger writes` gives touch input exclusively to
  ink and never interprets a double tap as viewport zoom.
- Returning to a page in the same editor session restores its mode, scale, and
  focus.
- The view menu exposes Fit Width and Fit Page. A transient percentage/status
  label uses `effectiveScale / fitWidthScale × 100` during pinch or command
  zoom and then leaves the writing area.
- If the transformed page is smaller than U on an axis, center it on that axis,
  including the vertical exception to first-visit top alignment. If larger,
  clamp pan while keeping exactly 72px of the page recoverable on that axis.

### Device and page rotation

Device rotation and window resizing:

1. Read the document point under the old usable-canvas center, or the active
   text/object anchor when keyboard avoidance is in progress.
2. Fit Width/Fit Page recompute from the new U and R. Custom preserves its
   absolute scale unless the documented Custom bounds require a clamp.
3. Place that same document point under the new usable-canvas anchor.
4. Clamp only after reprojecting.
5. Keep selected tool, current page, selection, and committed content intact.

Explicit page rotation:

- updates only `rotationQuarterTurns`;
- rotates PDF, template, ink, text, image, shape, selection, hit testing, and
  highlights together;
- reprojects the current document focus into the new rotated bounding box;
- keeps Fit Width/Fit Page mode and recomputes their derived scale from the new
  R dimensions; and
- preserves absolute scale in Custom mode, subject only to the documented
  Custom bounds.

Device orientation never updates page orientation or saved paper dimensions.

### Viewport-changing editor UI

- When the text keyboard opens, anchor the active text box into the remaining
  visible area without changing its document coordinates.
- When recording or playback controls appear, preserve the current document
  focus as the usable canvas height changes.
- If the OS cancels an active pointer during a metrics change, discard only the
  unfinished transient stroke. Never persist a partial stroke in the wrong
  coordinate space.
- Verify Flutter/system text selection handles in a focused implementation
  spike; regardless of mechanism, they must remain usable at the documented
  target size without double-applying page transforms.

### Legacy data gate

- Add integer `coordinateSpaceVersion` to every page JSON. Missing or integer
  `0` is unresolved legacy v0; integer `1` is canonical v1. A negative,
  non-integer, or greater-than-1 value is unsupported/corrupt read-only: never
  reinterpret it as v0, migrate it, downgrade it, or overwrite it.
- A legacy page with no coordinate-bearing strokes, text boxes, images, or
  shapes can be marked v1 without geometric conversion.
- The repository, not only the UI, blocks every page rewrite or mutation for a
  non-empty unresolved v0 page. That includes drawing, erasing, lasso/Smart
  Ink, text/image/shape changes, template or page rotation, and duplication.
  Navigation and raw backup remain available. Canonical pages in the notebook
  may still be edited without rewriting the legacy page. Save, copy, and
  duplicate paths preserve the source version exactly whenever they are
  allowed.
- Before conversion, create a recoverable notebook archive containing the
  original notebook index, all page JSON, all assets, a manifest, and checksums.
  PDF export is not a migration backup because it cannot restore editable
  content.
- The archive is a notebook-consistent snapshot: wait for that notebook's save
  queue to drain, acquire a notebook-level write lock, enumerate index/pages/
  assets, generate and verify the manifest/checksums, and publish the completed
  archive atomically before releasing the lock. Concurrent edits stay disabled
  during this operation, and any failure leaves no archive reported as
  recoverable.
- The new lowercase iOS bundle cannot directly read the old bundle's container.
  Recovery must first use an old-identifier build, an extracted Simulator
  container, or a device backup to produce the archive.
- If legacy content must be preserved, calibration is explicit, previewable,
  cancelable, and type-aware. Ink and shapes may share a confirmed legacy
  fitted-canvas scale, while existing image/text fields require separate
  inspection because some values were originally derived from document size.
  Mark the page v1 only after all coordinate-bearing types convert
  successfully; migration is atomic and idempotent.
- Never mix new canonical content into an unresolved legacy page and never
  guess a scale from sparse content bounds.

## Input And Gesture Ownership

| Input | Writing tool | Finger moves mode | Lasso / object mode |
|---|---|---|---|
| Apple Pencil / stylus | Draw or erase with the selected tool | Continues using selected tool | Selects or manipulates the active object/tool |
| One finger | Writes when `Finger writes` is active; double tap never zooms | Pans; double tap toggles smart zoom | Owned by the active selection/object gesture |
| Two fingers | Pinch and pan; never creates content | Pinch and pan | Pinch and pan unless an explicit two-handle transform is active |
| Mouse / trackpad | Click/drag uses active tool; hover shows labels | Space-drag or middle drag pans | Click/drag manipulates selection |
| Keyboard | Tool and command shortcuts | Arrow/Space-assisted view movement | Escape clears selection or closes transient UI |

Minimum shortcuts:

- Command-Z / Command-Shift-Z: undo / redo.
- Command-F: notebook search.
- P / H / E / L: Pen / Highlighter / Eraser / Lasso when focus is not in text.
- Space-drag: temporary pan with mouse/trackpad.
- Escape: close popover/panel or clear selection in reverse order.

Every gesture has a visible command alternative.

## User-Facing Copy

Prefer outcome labels over internal terms:

- `Pages`
- `Page 1 of 24`
- `Insert`
- `Finger writes`
- `Finger moves`
- `Writing assist`
- `Fit width`
- `Fit page`
- `Rotate page clockwise`
- `Undo ink stroke`
- `Redo ink stroke`
- `Delete selected ink? This can't be undone.`
- `Template unavailable on PDF pages`
- `Saved`, `Saving…`, `Couldn't save — Retry`
- `Microphone access is off — Open Settings`

Icon-only compact controls retain these exact labels as tooltips and semantics.
Color controls include a color name, such as `Teal pen, 3 pt`, rather than the
generic label `Color`.

## User Flow

1. **Open and write**
   - The notebook opens on the current page in its session view or first-visit
     Fit Width.
   - A new editor session visibly selects Black Pen 3pt.
   - Pencil can write immediately.
2. **Change a writing preset**
   - Tap a visible preset or the active preset button.
   - The dock updates the tool, named color, and width together.
   - Manual property changes show Custom and do not mutate the fixed preset.
   - The page and viewport do not move.
3. **Change detailed tool properties**
   - Tap the selected tool or property preview.
   - A popover anchored to that control exposes only relevant values.
   - Selecting a value updates the preview and closes only when the user taps
     outside or confirms a multi-step setting.
4. **Insert content**
   - Tap Insert, then Text, Image, or Shape.
   - File cancellation returns to the prior tool without a failure message.
   - Inserted content stays in document space; its viewport-projected handles
     stay upright and retain 44px targets.
5. **Select and use Smart Ink**
   - Tap Lasso and select strokes.
   - The selection action bar offers Smart Ink alongside Recolor and Delete.
   - Cancel returns to the selected ink without changing it.
6. **Navigate pages**
   - Tap `Page n of total`.
   - Choose Pages, Outline, or Bookmarks and select a destination.
   - Compact panels close after selection; pinned wide panels remain.
7. **Zoom and rotate**
   - Pinch, use View commands, or double-tap only in Finger moves.
   - The first content or view gesture locks a provisional fit into Custom.
   - Rotate/resize the device; focus stays on the same content.
   - Choose `Rotate page clockwise`; page content rotates as one unit and the
     working location remains in view.
8. **Recover**
   - `Undo ink stroke` / `Redo ink stroke` operate only on the current page's
     draw/erase history.
   - Deleting selected ink or a page requires confirmation that it cannot be
     undone.
   - Save, import, export, or permission errors retain current edits and provide
     Retry, Open Settings, or Dismiss as appropriate.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Loading page | Header identity, disabled tool dock, canvas progress | Back | Loading remains localized to canvas |
| Default writing | Selected tool and preset, fixed paper, page count | All applicable writing/navigation actions | No persistent instructional overlay |
| First empty page | Default writing plus a short hint in the workspace margin | Write, dismiss, change touch mode | Hint disappears after first content action |
| Tool properties open | Anchored labelled popover | Change property, outside tap, Escape | Page position and selection are preserved |
| Finger moves | Touch mode visibly selected | One-finger pan, Pencil editing, pinch | Tooltip explains Pencil remains active |
| Lasso selecting | Lasso selected, no unrelated color/width row | Draw selection, cancel | Escape or Clear returns to lasso-ready state |
| Lasso selected | Bounds/handles plus upright action bar | Move, resize, recolor, Smart Ink, delete, clear | Delete confirms that current history cannot undo it |
| Recording | Red elapsed status control | Continue writing, stop recording | Permission denial offers Open Settings |
| Playback | Compact transport status row | Play/pause, scrub, follow, close | Viewport anchor survives bar appearance |
| Import/export busy | Progress in invoking command or modal | Cancel if operation supports it; keep writing when safe | Completion or actionable error message |
| Saving | Small title status | Continue editing | Success becomes quiet; failure exposes Retry |
| PDF page | PDF indicator; template action disabled/explained | Annotate, bookmark, rotate, export | No misleading template picker |
| Navigator open | Pages/Outline/Bookmarks and selected page | Navigate, manage pages, close | Overlay blocks canvas input, traps focus, and restores focus on close |
| Resize/orientation change | Same page/tool/content focus in new shell density | Continue editing | No automatic document mutation or whole-page jump |
| Creating raw backup | Blocking progress after saves drain | Cancel only before snapshot lock; no editing during snapshot | Success only after manifest/checksum verification and atomic publish |
| Legacy page awaiting decision | Read-only compatibility notice or migration flow | Back up, calibrate, postpone | Never mix new canonical edits into unresolved legacy coordinates |
| Unsupported/corrupt page version | Read-only compatibility error with version value | Raw backup, close | Never downgrade, calibrate, duplicate, or overwrite |

## Accessibility

- Every important target is at least 44×44 logical pixels.
- Header focus order follows Back, Navigator, title/status, Undo, Redo, visible
  commands, More; tool dock follows the visual order; navigator follows tabs,
  pages, and page actions.
- The active tool announces tool, color, width, and selected state.
- Touch mode announces `Finger writes, selected` or `Finger moves, selected`.
- Color swatches include names and a non-color selection indicator.
- Disabled actions expose the reason when it is useful.
- Normal text meets at least 4.5:1 contrast; icons, focus indicators, selected
  outlines, and meaningful non-text boundaries meet at least 3:1.
- Closing a popover, menu, sheet, or overlay navigator returns focus to the
  control that opened it.
- Save, import, export, recording, permission, and migration results are
  announced through visible text and an accessible live-region update.
- At 200% text scaling, compact layouts keep icons and move long labels into
  popovers/tooltips without clipping core actions.
- Reduced-motion mode removes nonessential dock/panel motion and keeps rotation
  or resize reprojection immediate.
- Canvas gestures are not the only route to zoom, navigation, selection clear,
  or page rotation.

## Edge Cases

- One-page notebook: Pages remains useful for Add and page actions but does not
  reserve permanent space.
- Very large or unusual PDF dimensions: Fit Width and Fit Page use the stored
  page size; no normalization to the default blank-page ratio.
- Rotated PDF with text-search highlights: all layers share the same page
  transform and remain aligned.
- Page switch during audio follow: existing follow/suspend behavior remains,
  and the destination page restores or establishes its viewport state.
- Lasso selection plus touch-mode change: block the change and show
  `Clear the ink selection before changing finger mode`; do not silently clear
  or transform the selection.
- File picker cancellation: no error snackbar and no viewport reset.
- Permission denial: keep the editor usable and offer a settings path.
- Save failure: retain in-memory edits and do not report `Saved`.
- Window becomes smaller than control minimums: lower-priority header actions
  enter More; primary tools never shrink below target size.
- Legacy page with mixed coordinate bases: do not guess a destructive automatic
  scale.

## UI Acceptance Criteria

- [ ] The primary path from opening a notebook to writing needs no intermediate
  dialog or mode change.
- [ ] Header and tool dock have distinct command roles and no hidden horizontal
  scroll at the three required iPad test sizes.
- [ ] Tool properties are contextual and every tool has a valid, visible,
  independently remembered setting.
- [ ] A new session starts with Black Pen 3pt; four fixed presets remain
  unchanged when manual settings produce a labelled Custom configuration.
- [ ] Current tool, preset, touch behavior, recording state, and disabled state
  are recognizable without relying on color alone.
- [ ] Insert uses labelled Text, Image, and Shape choices; Smart Ink appears
  after ink selection.
- [ ] The page navigator replaces the permanent bottom strip and preserves all
  existing page operations.
- [ ] Wide pinned, portrait overlay, and narrow modal navigator modes preserve
  the same current page and editor state.
- [ ] Navigator empty states, last-page deletion, current-page deletion,
  modal focus trapping, canvas input blocking, and focus restoration follow the
  documented rules.
- [ ] The document surface always has the persisted page dimensions, and every
  content/input layer round-trips through the same transform.
- [ ] q0–q3 use the documented normalized clockwise D→R mappings; document
  content transforms with the page while operation handles remain upright and
  at least 44px.
- [ ] Device rotation, Split View resize, keyboard appearance, and audio-bar
  appearance preserve content coordinates and the intended viewport focus.
- [ ] Fit Width, Fit Page, and Custom modes are explicit and testably distinct.
- [ ] The first pan, zoom, or content gesture locks a fit view into Custom;
  Custom scale limits, Finger-moves-only double tap, zoom steps, and the exact
  72px pan clamp are testable.
- [ ] Explicit page rotation keeps controls upright, content aligned, and the
  working location visible.
- [ ] Loading, cancellation, permission denial, busy, save failure, and legacy
  compatibility states have visible recovery behavior.
- [ ] Undo/redo is labelled and scoped to current-page draw/erase history;
  non-reversible selected-ink and page deletion require confirmation.
- [ ] Lasso is ink-only and finger-mode changes are blocked while a selection
  remains active.
- [ ] Page-level coordinate versioning, raw archive, repository write gates,
  atomic conversion, and idempotent legacy fixtures prevent v0/v1 mixing.
- [ ] Unknown, invalid, or future coordinate versions remain read-only and are
  never treated as legacy; save/copy/duplicate paths preserve valid versions.
- [ ] Raw archive drains pending saves and holds a notebook write lock through
  verified, atomic publication, with no false recoverable success on failure.
- [ ] Semantics, focus order, keyboard alternatives, 200% text scaling, reduced
  motion, contrast, and 44px targets meet this specification.

## Verification

- Widget tests:
  - Open and write without configuration.
  - Switch tools/presets and verify independent settings.
  - Open Insert and selection-context Smart Ink.
  - Open/close/pin the navigator and preserve page selection.
  - Verify navigator empty states, deletion constraints, modal input blocking,
    focus trap, and focus restoration.
  - Verify ink-only undo labels, disabled states, and non-reversible deletion
    confirmation.
  - Verify all existing commands remain reachable through their new hierarchy.
  - Verify loading, disabled, cancellation, permission, and error feedback.
- Viewport unit tests:
  - Exact normalized q0–q3 corner mappings and
    document→viewport→document round trips.
  - Pinch focal-point invariance and pan under rotated pages.
  - Fit Width, Fit Page, gesture-to-Custom, scale bounds, 1.25/0.8 zoom steps,
    Finger-moves-only double-tap toggle, and exact 72px clamp rules.
  - Viewport resize and page rotation anchor preservation.
  - Per-page transient viewport restoration.
- Responsive and semantic tests:
  - 834×1194 portrait.
  - 1194×834 landscape.
  - 600×800 Split View.
  - 200% text scaling, reduced motion, focus order, unique labels, and 44px
    targets.
- Alignment tests:
  - Place ink, text, image, shape, template geometry, PDF search highlight, and
    lasso target near the lower-right page corner.
  - Resize and rotate the device and page.
  - Confirm editor, thumbnail, hit testing, persistence, and PDF export all
    resolve the same document location.
- Legacy tests:
  - Missing page version classifies as v0; empty v0 upgrades losslessly.
  - Negative, non-integer, and greater-than-1 versions remain unsupported/
    corrupt read-only and cannot be migrated or overwritten.
  - Repository blocks every mutation of non-empty unresolved v0 pages while
    canonical pages remain editable; allowed save/copy/duplicate paths preserve
    the page version.
  - Raw archive includes original JSON/assets plus a verified manifest and
    checksums, drains pending saves, blocks concurrent notebook writes, and
    publishes atomically.
  - Archive failure never reports a recoverable backup or leaves a partial
    archive at the destination.
  - Type-aware conversion is atomic, cancelable, and idempotent; failed
    conversion leaves the original page and archive unchanged.
- Golden tests:
  - Default Pen in portrait and landscape.
  - Tool properties open.
  - Lasso selection context.
  - Pinned and overlay navigator.
  - Recording/playback.
  - Narrow Split View.
- Manual real-iPad checks:
  - Pencil latency and palm/touch ownership.
  - Pinch/pan while writing.
  - Portrait↔landscape, Split View, and Stage Manager resizing.
  - Keyboard avoidance for text.
  - Microphone and file/photo permission recovery.

## Implementation Handoff

Implementation order is intentional:

1. Resolve the permanent bundle identity and extract a raw recoverable archive
   from every legacy container that must survive.
2. Add page-level coordinate versioning, a legacy classifier, repository write
   gates, and old-JSON fixtures before opening legacy pages in a writable
   canonical editor.
3. Extract and test pure D↔R↔V transforms, fit/clamp rules, and the editor-level
   per-page session controller.
4. Move fixed `W × H` document content and viewport-projected operation layers
   onto that contract, removing layer-specific screen-coordinate persistence.
5. Verify editor, thumbnail, search highlight, hit testing, persistence, and
   export alignment.
6. Introduce the responsive header, tool dock, navigator, and editor theme
   tokens, then reconnect current commands and feedback.
7. Complete responsive, semantic, migration, golden, performance, export, and
   real-device QA.

The fixed-coordinate and transform work is a release gate for the new visual
shell, not a later cleanup.

## Implementation Review

- Status: Implemented on 2026-07-27 for canonical v1 pages.
- Delivered:
  - Fixed `W × H` document layout with one tested D↔R↔V viewport transform.
  - Fit Width first visit, explicit Fit Page, Custom gesture lock, exact
    recoverability clamps, rotation/reflow focus preservation, and per-page
    in-session viewport memory.
  - Responsive document header with grouped overflow actions.
  - Non-scrolling Pen/Highlighter/Eraser/Lasso/Insert dock, contextual
    properties, independent tool settings, complete presets, and explicit
    finger behavior.
  - Smart Ink in the upright Lasso selection context.
  - No permanent bottom strip or floating favorites bar; narrow/standard
    layouts use an overlay navigator and wide layouts can pin a
    Pages/Outline/Bookmarks panel.
  - Page coordinate v1, lossless empty-v0 upgrade, repository write gates, and
    visible read-only treatment for non-empty legacy/unsupported pages.
- Intentional implementation differences:
  - Zoom/Fit remains a compact viewport control instead of being duplicated in
    the document More menu.
  - Standard iPad widths use a full-height left modal; widths below 720 use a
    bottom sheet better suited to the compact viewport.
  - The Lasso command bar is projected upright, while image/text/shape
    operation handles still inherit the page transform and require real-device
    follow-up before a broader viewport-space handle refactor.
- Remaining release gates:
  - No non-empty v0 conversion is offered until the old app-container decision
    and verified raw archive flow are complete.
  - Complete real-iPad Pencil, palm rejection, Split View, Stage Manager,
    keyboard, 200% text, golden, dense-page performance, and large-PDF QA.
