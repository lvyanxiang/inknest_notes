# Developer Local Data Reset Product Brief

- Status: Accepted
- Size: Medium
- Updated: 2026-09-11
- Roadmap link: `docs/development/POST_MVP_ROADMAP.md#persistence`

## Problem

Developers testing local-first and cloud synchronization flows need a reliable
way to return an installed build to a known local state. Requiring deletion of
the app is slow, iOS offloading may preserve Documents data, and deleting
notebooks through the normal library flow intentionally creates synchronization
mutations that change cloud state.

## Recommended Outcome

Add Debug-build-only Developer tools to Account. Make the combined notebook and
sync-state reset the recommended first action because it creates a coherent
clean restore boundary. Keep separate notebook-files-only and sync-state-only
actions for targeted diagnostics, with explicit warnings that notebook files
alone do not reset an already-advanced sync Cursor. Every action signs out
first, waits for active synchronization to finish, and deletes only the
selected app directories without invoking normal notebook deletion callbacks.
Preserve the installation identifier so developers can continue testing the
same logical device.

## Scope

- In scope:
  - A Debug-only entry in Account for signed-in and signed-out states.
  - Separate notebook, sync-state, and combined reset actions.
  - Destructive confirmation, busy protection, success/error feedback, and an
    immediate library refresh.
  - Safe coordination with an already-running synchronization cycle.
- Non-goals:
  - A production user-facing data-management feature.
  - Cloud account/content deletion or creation of cloud Tombstones.
  - Resetting the Keychain installation identifier.
  - Replacing the future Recently Deleted feature for ordinary users.

## User Flow

1. In a Debug build, open Account and scroll to Developer tools.
2. Choose the recommended combined reset or a diagnostic scope and review the
   confirmation that describes exactly what remains and that any active account
   will be signed out.
3. Confirm; the app waits for active sync, signs out, clears the selected local
   data, refreshes the library, and reports completion.

## Acceptance Criteria

- [x] Developer tools are absent from Profile/Release builds.
- [x] Clearing local notebooks removes notebook/folder/assets data without
  invoking repository deletion callbacks or queuing cloud deletion.
- [x] The notebook-files-only confirmation explains that retained mappings and
  Cursor do not represent a clean cloud-restore state.
- [x] Clearing sync state removes account/device sidecars and signed-out
  mutation journals while leaving notebook content intact.
- [x] Combined reset removes both scopes and leaves the app signed out while
  preserving its installation identifier.
- [x] Cancel leaves all data unchanged; repeated taps are disabled while a
  reset is running; failures explain that the reset was incomplete.
- [x] The library reflects the remaining local data without reinstalling the
  app.

## Alternatives And Tradeoffs

- Option: Tell developers to delete the app or manually remove sandbox files.
- Why not now: It is slower, not self-documenting, and iOS offloading can retain
  the exact data a developer intended to clear.

## Dependencies And Risks

- Product or technical dependency: The library owns automatic synchronization,
  so it must coordinate the reset rather than letting Account delete files in
  isolation.
- Data, privacy, performance, or migration risk: The action is intentionally
  destructive. Debug-only visibility, scoped directory deletion, explicit
  confirmation, and sign-out reduce accidental cloud or release impact.

## Open Decisions

- None.

## Delivery

- UI/UX spec: `docs/product/features/developer-local-data-reset/UI_UX_SPEC.md`
- Implementation status: Delivered
- Verification: 339 Flutter tests passed; `flutter analyze` reports no issues.
