---
name: inknest-project
description: Project workflow for continuing the InkNest Notes Flutter app across many sessions. Use when Codex is asked to resume, plan, implement, verify, or mark roadmap tasks for this repository, including MVP milestones in docs/development/ROADMAP.md and post-MVP GoodNotes/Notability-style work in docs/development/POST_MVP_ROADMAP.md, while avoiding rereading the whole project.
---

# InkNest Project

Use this skill to continue the InkNest Notes project with minimal context reload.
Treat the repository documents as the source of truth, not prior conversation.

This is a development-only skill. Do not update
`docs/academic/GRADUATION_TASK_BOOK.md`,
`docs/academic/OPENING_REPORT.md`, or academic reference lists as a routine
side effect of code or roadmap work. Use `$inknest-academic-docs` only when the
user explicitly asks to maintain graduation academic documents.

## Context Recovery

Start each substantial task by reading only:

1. `docs/development/STATUS.md`
2. The active planning document:
   - Read `docs/development/POST_MVP_ROADMAP.md` when `docs/development/STATUS.md` says the project is in post-MVP planning, polish, or a `Post-MVP` milestone.
   - Read the relevant section of `docs/development/ROADMAP.md` for MVP milestones or if the user explicitly asks about paused sync/backup work.
3. The files directly named by the current task

Avoid scanning the whole repository unless the status file is missing, stale, or
the current task crosses unknown boundaries.

Ignore `docs/academic/` during normal development context recovery unless the
user's current request is specifically about academic documents.

Treat `docs/development/STATUS.md` as the active pointer. Treat
`docs/development/ROADMAP.md` as the source of truth for MVP milestones and
paused Milestone 8 state. Treat `docs/development/POST_MVP_ROADMAP.md` as the
source of truth for post-MVP feature work.
If documents disagree, use the active planning document for checklist state and
update `docs/development/STATUS.md` after verifying the code.

Do not resume Milestone 8 sync and backup by default. It is paused unless the
user explicitly asks to work on sync, backup, restore, conflicts, iCloud,
WebDAV, or a backend.

## Work Loop

For each user request:

1. Identify the current phase and first unfinished task from the active planning document.
2. Read only the smallest useful set of code files.
3. Implement the requested task or the next roadmap task.
4. Validate economically:
   - During implementation, run only the smallest directly related test.
   - After a failure, rerun only the failed test until it passes.
   - Near completion, run the full `flutter test` suite and `flutter analyze`
     at most once each unless the final fix changes production code.
   - Do not rerun Flutter validation after documentation-only changes.
   - Do not run native platform builds by default. Run one only when the user
     requests it or a platform-specific failure cannot be resolved otherwise.
5. Mark completed active-plan items with `[x]` when they are checklist items. If the active post-MVP section uses plain bullets, either convert only the immediate task list to checkboxes before executing it or record concise progress in `docs/development/STATUS.md`.
6. Update `docs/development/STATUS.md` with current milestone, next task, decisions, and verification.

If validation cannot run, record the reason in the final response. Do not mark a
roadmap task complete unless the implementation is present and at least a
reasonable check has been attempted.

## Project Preferences

- Prefer iPadOS/iOS-first decisions for product tradeoffs.
- Prioritize handwriting latency, persistence, and editing reliability.
- Build the first version as paged notebooks, not an infinite canvas.
- Keep app startup focused on the notebook library.
- After the MVP export milestone, prefer polishing high-frequency GoodNotes /
  Notability-style workflows before returning to sync.
- In post-MVP work, start with editor usability unless the user chooses a
  different post-MVP milestone.
- Keep implementation close to Flutter conventions and the existing repo style.
- Use feature folders under `lib/features` and shared models/storage under
  `lib/models` and `lib/storage`.

## Status File Format

Keep `docs/development/STATUS.md` short and easy to rewrite:

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
