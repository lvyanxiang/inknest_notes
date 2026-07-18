# InkNest Product Standards

## Product Priorities

Evaluate product choices in this order:

1. Handwriting latency, persistence, and editing reliability.
2. Clear iPadOS/iOS-first study and note-taking workflows.
3. Safe, understandable local data behavior and recovery.
4. Frequent user value before breadth or competitor parity.
5. Cross-platform expansion only after the primary notebook workflow is solid.

InkNest remains a paged notebook product. Preserve startup at the notebook
library and avoid turning the editor into an infinite canvas without an
explicit strategy decision.

## Decision Criteria

Score options qualitatively against:

- User frequency and severity of the problem.
- Fit with handwriting, PDF study, and mixed-note workflows.
- Discoverability and cognitive load.
- Reliability, reversibility, and data-loss risk.
- Implementation and maintenance cost.
- Performance on large notebooks.
- Accessibility and input-device coverage.
- Compatibility with existing persisted notebooks.

Prefer the smallest coherent version that proves value without creating a
dead-end data model or interaction.

## Scope Rules

- Separate current delivery from future extensions.
- Do not package optional future ideas as acceptance criteria.
- Treat sync, accounts, cloud storage, collaboration, monetization, AI, mobile,
  and Web as material scope changes.
- Define migration and rollback behavior for persisted model changes.
- Preserve existing notebooks unless the user explicitly approves migration.
- Prefer reversible actions and visible recovery for destructive workflows.

## Acceptance Criteria Quality

Write criteria as observable outcomes. Cover:

- Entry point and primary success path.
- Empty, loading, disabled, cancellation, error, and retry behavior where
  relevant.
- Persistence across page changes and app restart when data changes.
- Existing notebook compatibility.
- Large or unusual documents when the feature touches PDF or storage.
- Platform or input-device differences.

Avoid implementation details unless they are product constraints.

## Requirement Levels

- Small: no standalone brief unless the behavior is likely to be disputed
  later.
- Medium: brief required; UI/UX spec required for visible behavior.
- Large: brief and UI/UX spec required, with explicit user approval before
  implementation if any strategic choice remains open.
