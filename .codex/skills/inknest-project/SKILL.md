---
name: inknest-project
description: Project workflow for continuing the InkNest Notes Flutter app across many sessions. Use when Codex is asked to resume, plan, implement, verify, or mark roadmap tasks for this repository, especially to avoid rereading the whole project and to determine the next incomplete step from docs/ROADMAP.md and docs/STATUS.md.
---

# InkNest Project

Use this skill to continue the InkNest Notes project with minimal context reload.
Treat the repository documents as the source of truth, not prior conversation.

## Context Recovery

Start each substantial task by reading only:

1. `docs/STATUS.md`
2. The relevant section of `docs/ROADMAP.md`
3. The files directly named by the current roadmap task

Avoid scanning the whole repository unless the status file is missing, stale, or
the current task crosses unknown boundaries.

If `docs/STATUS.md` and `docs/ROADMAP.md` disagree, trust `docs/ROADMAP.md` for
completed checklist state and update `docs/STATUS.md` after verifying the code.

## Work Loop

For each user request:

1. Identify the current milestone and first unchecked task.
2. Read only the smallest useful set of code files.
3. Implement the requested task or the next roadmap task.
4. Run focused validation, normally `flutter test` and `flutter analyze` after code changes.
5. Mark completed roadmap items with `[x]`.
6. Update `docs/STATUS.md` with current milestone, next task, decisions, and verification.

If validation cannot run, record the reason in the final response. Do not mark a
roadmap task complete unless the implementation is present and at least a
reasonable check has been attempted.

## Project Preferences

- Prefer iPadOS/iOS-first decisions for product tradeoffs.
- Prioritize handwriting latency, persistence, and editing reliability.
- Build the first version as paged notebooks, not an infinite canvas.
- Keep app startup focused on the notebook library.
- Keep implementation close to Flutter conventions and the existing repo style.
- Use feature folders under `lib/features` and shared models/storage under
  `lib/models` and `lib/storage`.

## Status File Format

Keep `docs/STATUS.md` short and easy to rewrite:

```markdown
# InkNest Notes Status

## Current

- Milestone:
- Next task:
- Last completed:

## Decisions

- ...

## Verification

- ...

## Notes

- ...
```

Update this file after each meaningful implementation step. It should help the
next session resume quickly, not serve as a full changelog.
