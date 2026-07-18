---
name: inknest-ui-ux
description: UI/UX design and review workflow for InkNest Notes. Use whenever an InkNest requirement adds or changes a visible screen, editor tool, navigation path, dialog, sheet, feedback state, gesture, accessibility behavior, responsive layout, or iPad, phone, or Web interaction. Produce an implementation-ready flow, state model, layout and interaction specification, usability recommendation, and durable design records before code changes. Use with inknest-product-manager and inknest-project.
---

# InkNest UI/UX

Turn accepted product behavior into a complete, implementation-ready user
experience that fits InkNest's existing visual language and iPad-first input
model.

## Recover Context

Read only:

1. The current product brief, or the user's accepted behavior if no brief is
   required.
2. `references/ui-ux-standards.md` from this skill.
3. The existing screen, theme, reusable widgets, and tests directly affected.
4. Any existing `UI_UX_SPEC.md` for the same feature.

Inspect the running UI or screenshots when visual or responsive behavior cannot
be understood reliably from code. Do not use Figma or generate mockup images
unless the user explicitly asks for them.

## UX Workflow

1. Define the user goal and entry point.
2. Map the shortest primary flow and any exit, cancel, undo, or recovery path.
3. Enumerate relevant UI states: default, pressed, selected, disabled, empty,
   loading, success, error, offline, permission denied, and destructive
   confirmation.
4. Define information hierarchy, component placement, labels, and feedback.
5. Check Pencil, finger, mouse/trackpad, and keyboard behavior where relevant.
6. Check iPad portrait and landscape; include phone or Web only when in scope.
7. Specify accessibility semantics, focus order, text scaling, target sizes, and
   contrast expectations.
8. Reuse current components and theme tokens before proposing a new pattern.
9. Identify interaction conflicts, especially canvas drawing, pan, lasso,
   selection, zoom, and modal gestures.
10. Define UI verification: widget behavior, responsive constraints, semantics,
    and visual regression coverage proportional to risk.

Lead with one recommended design. Present alternatives only for meaningful
tradeoffs, not for cosmetic variety.

## Output Contract

Provide only the detail needed for implementation:

- UX recommendation and rationale.
- Entry point and step-by-step flow.
- State and feedback matrix.
- Layout and component specification.
- Input, responsive, and accessibility behavior.
- Edge cases and UI acceptance criteria.

For a clear implementation request, continue to code after the specification
unless a material interaction choice needs the user. Do not redesign unrelated
surfaces.

## Persistent Records

- Small: keep the design rationale in the response and relevant tests.
- Medium or Large: copy `assets/ui-ux-spec-template.md` to
  `docs/product/features/<feature-slug>/UI_UX_SPEC.md` before implementation.
- Accepted reusable UI pattern: append one concise row to
  `docs/design/UI_UX_DECISIONS.md`.
- Feature-specific choices belong in the feature spec, not the global log.

Update an existing spec when behavior changes. Keep product scope in
`PRODUCT_BRIEF.md` and interaction detail in `UI_UX_SPEC.md`.

## Implementation Handoff

Give `$inknest-project`:

- Exact affected screens and reusable components.
- Complete state behavior and visible copy.
- Interaction priority and gesture ownership.
- Responsive and accessibility constraints.
- UI-focused acceptance criteria and validation plan.

After implementation, review the result against the spec. Record intentional
deviations instead of silently leaving documentation stale.

## Completion Gate

UI/UX work is ready only when:

- The primary path is obvious and minimal.
- Important states and recovery paths are defined.
- Canvas and input gestures do not conflict.
- Portrait, landscape, and accessibility behavior are covered when relevant.
- Existing design patterns are reused or a new pattern is justified.
- The handoff can be verified through concrete UI behavior.
