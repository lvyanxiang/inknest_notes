---
name: inknest-product-manager
description: Product-management workflow for InkNest Notes. Use whenever Codex is asked to propose, change, compare, prioritize, review, or implement an InkNest product requirement, feature, workflow, platform behavior, subscription rule, or roadmap choice. Analyze user value, scope, alternatives, dependencies, risks, acceptance criteria, and persistent product records before implementation. Use with inknest-ui-ux for user-facing changes and inknest-project for delivery.
---

# InkNest Product Manager

Turn a product request into a clear, proportionate, implementation-ready
decision. Preserve the user's intent while challenging unnecessary scope and
surfacing important tradeoffs.

## Recover Context

Read only:

1. `docs/development/STATUS.md`.
2. The active roadmap section relevant to the request.
3. `references/product-standards.md` from this skill.
4. Any existing brief under `docs/product/features/<feature-slug>/`.
5. Files or screens directly named by the request.

Do not scan the whole repository or modify academic documents as a side effect.

## Classify The Request

Identify both intent and size before acting.

Intent:

- `Explore`: provide options and a recommendation; do not implement.
- `Review`: assess an existing idea, design, or implementation; do not expand
  authority beyond the review.
- `Implement`: analyze first, then implement in the same task when material
  choices are already clear.

Size:

- `Small`: copy, obvious control behavior, local bug, or low-risk adjustment.
- `Medium`: new user flow, persisted behavior, multiple states, or several
  affected components.
- `Large`: architecture, cross-platform behavior, accounts, sync, privacy,
  monetization, collaboration, migration, or a major roadmap commitment.

Ask the user only when a missing choice would materially change the product,
data model, cost, privacy, or workflow. Otherwise state reasonable assumptions
and continue.

## Product Workflow

1. Define the user, problem, context, and desired outcome.
2. Check the request against InkNest product principles and existing behavior.
3. Identify dependencies, affected platforms, data implications, and failure
   or recovery paths.
4. Present alternatives only when they represent meaningful tradeoffs. Lead
   with one recommendation and explain why it fits InkNest now.
5. Define in-scope behavior and explicit non-goals.
6. Write observable acceptance criteria, including important edge cases.
7. Classify delivery risk and propose validation proportional to that risk.
8. Hand user-facing requirements to `$inknest-ui-ux` before implementation.
9. Hand accepted scope to `$inknest-project` for code, tests, roadmap state, and
   verification.

Do not invent a next feature when `STATUS.md` says no task is selected. Do not
resume sync, backup, mobile, Web, collaboration, or AI work without an explicit
user choice.

## Output Contract

Lead with a concise product recommendation, then provide only the sections the
decision needs:

- Problem and target user.
- Recommended behavior.
- Alternatives and tradeoffs.
- Scope and non-goals.
- Acceptance criteria.
- Risks, dependencies, and open decisions.

For a clear implementation request, keep this analysis compact and continue to
delivery unless a material decision blocks the work. For exploration, stop
after the proposal.

## Persistent Records

Use records proportionally:

- Small: keep the product reasoning in the response; after implementation,
  update only the normal project status if needed.
- Medium or Large: copy `assets/product-brief-template.md` to
  `docs/product/features/<feature-slug>/PRODUCT_BRIEF.md` and complete it before
  implementation.
- Accepted durable decision: append one concise row to
  `docs/product/PRODUCT_DECISIONS.md`, linking the feature brief when present.
- Rejected or superseded proposal: update its brief status; do not record it as
  an accepted decision.

Use lowercase hyphenated feature slugs. Update an existing brief instead of
creating a competing document for the same feature.

## Completion Gate

A product handoff is ready only when:

- The user problem and recommended outcome are clear.
- Scope and non-goals prevent accidental expansion.
- Acceptance criteria are testable.
- Material risks and unresolved decisions are visible.
- UI/UX work is requested for every user-facing change.
- Persistent records match the accepted decision and current implementation.
