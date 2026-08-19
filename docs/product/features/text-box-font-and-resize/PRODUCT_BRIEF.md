# Text Box Font And Resize Product Brief

- Status: Delivered
- Size: Medium
- Updated: 2026-08-19
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md#post-mvp-4-rich-notes`

## Problem

Typed notes currently have a fixed-width text box and a one-tap simulated
handwriting toggle. Users cannot directly control wrapping by resizing the
box, and the simulated system-font fallback is weaker than the three real
handwriting fonts already bundled for Smart Ink.

## Recommended Outcome

Make text boxes directly resizable and give them an explicit font picker.
Keep the platform default font for compatibility and offer the three bundled
handwriting fonts as real font-family choices. Remove the old simulated
handwriting style without changing Smart Ink recognition or Beautify.

## Scope

- In scope: paged and infinite-canvas text boxes, horizontal width resizing,
  automatic wrapping inside the chosen width, manual line breaks, font
  selection, persistence migration, PDF export, and tests.
- Non-goals: removing or changing ML Kit, Smart Ink, Beautify, font-to-stroke
  redraw, rich-text spans, vertical resizing, or font download.

## User Flow

1. Insert or select a text box.
2. Type text, choose a font from the text-box header, and drag the resize
   handle to control wrapping.
3. Move or delete the box with the existing controls; changes persist and
   export with the notebook.

## Acceptance Criteria

- [x] Text boxes expose Default, 刘建毛草, 龙藏, and 芝麻行 font choices.
- [x] The three handwriting choices render with their bundled font files,
  without system-font fallback, forced italic, or synthetic weight styling.
- [x] Dragging the resize handle changes and persists box width within the
  available paged surface; text wraps at that width and preserves manual
  newlines.
- [x] Paged and infinite-canvas editors share the same text-box interaction.
- [x] Existing `regular` text boxes remain default-font text; legacy
  `handwriting` boxes migrate to 刘建毛草 instead of simulated styling.
- [x] Smart Ink and Beautify behavior and tests remain intact.

## Alternatives And Tradeoffs

- Keep a one-tap style toggle: rejected because it hides the selected font and
  cannot represent three real choices.
- Remove the default font: rejected because it would silently restyle existing
  typed notes.

## Dependencies And Risks

- Depends on the three font assets already declared in `pubspec.yaml`.
- Persisted text-box JSON needs backward-compatible decoding of the old
  `style` field.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/text-box-font-and-resize/UI_UX_SPEC.md`
- Implementation status: Delivered
- Verification: `flutter analyze`, all 267 Flutter tests, and
  `git diff --check` pass.
