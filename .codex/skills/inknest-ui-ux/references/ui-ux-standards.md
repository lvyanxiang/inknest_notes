# InkNest UI/UX Standards

## Experience Principles

- Keep writing and reading as the dominant editor activities.
- Prefer direct manipulation, visible state, and reversible actions.
- Keep frequent actions close; move rare or destructive actions into menus or
  confirmation flows.
- Preserve canvas position, selection, and unsaved work across non-destructive
  dialogs whenever possible.
- Use concise labels that describe the outcome, not internal implementation.
- Avoid adding permanent toolbar controls for infrequent features.

## iPad And Input

- Prioritize Apple Pencil latency and uninterrupted stroke capture.
- Give each gesture one clear owner. A gesture must not simultaneously draw,
  pan, select, or resize.
- Keep finger pan behavior understandable when Pencil writing is active.
- Support mouse/trackpad hover and keyboard focus when practical, without
  weakening touch behavior.
- Test both portrait and landscape, including narrow split-view widths when the
  feature affects editor layout.

## Layout And Components

- Reuse the app theme, existing dialogs, sheets, snackbars, toolbar patterns,
  thumbnail actions, and semantic colors.
- Use theme spacing and typography consistently; avoid one-off styling when an
  existing component communicates the same hierarchy.
- Keep primary actions visually distinct and destructive actions clearly
  separated.
- Keep interactive targets at least 44 logical pixels where layout permits.
- Prevent important controls from being hidden by safe areas, keyboards, or
  compact widths.
- Use progressive disclosure for advanced settings.

## State And Feedback

Define only applicable states, but never omit foreseeable failure behavior:

- Default, selected, disabled, busy, and completed.
- Empty content and first-use guidance.
- Permission denial, file cancellation, invalid input, and retry.
- Destructive confirmation plus recovery or undo where feasible.
- Long-running progress and cancellation when the user could otherwise assume
  the app is frozen.

Feedback should identify the result and, for errors, the next useful action.

## Accessibility

- Add semantic labels and tooltips for important icon-only actions.
- Preserve logical focus and reading order.
- Do not encode meaning by color alone.
- Maintain readable contrast and support text scaling without clipping key
  actions.
- Announce meaningful asynchronous results through visible accessible feedback.
- Avoid gestures as the only route to important functionality.

## Canvas-Specific Checks

- Confirm coordinate transforms for zoom, rotation, page fitting, and hit
  testing.
- Keep floating controls upright when the page surface rotates.
- Verify selection, search highlights, PDF backgrounds, images, text, shapes,
  and strokes share the intended transform.
- Do not place translucent overlays where they obscure handwriting precision.
- Confirm that modal sheets and tool changes save or preserve current edits.

## UI Validation

Choose validation proportional to risk:

- Widget tests for entry points, state changes, validation, and feedback.
- Responsive tests for materially different widths or orientations.
- Semantic tests for important accessible actions.
- Golden tests only when exact visual regression is important and stable.
- Real iPad QA for Pencil, multi-touch, performance, permissions, or platform
  integrations that simulators cannot represent reliably.
