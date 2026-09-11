# Developer Local Data Reset UI/UX Specification

- Status: Accepted
- Updated: 2026-09-11
- Product brief: `docs/product/features/developer-local-data-reset/PRODUCT_BRIEF.md`
- Affected surfaces: Account, notebook library refresh

## Recommendation

Place a visually separated Developer tools section at the bottom of Account in
Debug builds. Put the combined local-data reset first and label it recommended;
keep partial scopes as diagnostic actions. Use labelled list rows instead of
permanent library controls because reset is rare and destructive. Each row
opens a scope-specific confirmation dialog; no action begins from the first
tap.

## User Flow

1. Open Account from the library header and scroll to Developer tools.
2. Tap Clear local data (recommended), Clear notebook files only, or Reset sync
   state.
3. Review the exact deletion scope and choose Cancel or the destructive action.
4. On confirmation, controls disable and show progress. On success, Account
   stays open, the current account is signed out, and a SnackBar reports the
   result. On failure, an inline accessible error remains retryable.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Default | Three labelled rows with scope descriptions | Open any confirmation | Copy distinguishes local notes, sync state, cloud data, and device identity |
| Confirmation | Destructive title and exact consequences | Cancel or confirm | Cancel closes without changes |
| Busy | Progress indicator on the chosen row; all rows disabled | None | Wait for active sync/sign-out/reset |
| Success | Default section | Any action | Accessible SnackBar names the completed scope |
| Error | Inline error container below the section | Retry any action | Message states reset may be incomplete |

## Layout And Components

- Placement and hierarchy: Bottom of the existing Account card, separated by a
  divider and a `Developer tools · Debug only` heading.
- Reused components: `ListTile`, `AlertDialog`, error container, and `SnackBar`.
- New component or pattern, if justified: None; the section is feature-local.
- User-facing copy: English, matching the current English-only release policy.

## Input And Responsive Behavior

- Pencil and touch: Every row uses the full standard tap target; no gesture-only
  interaction.
- Mouse/trackpad and keyboard: Native ListTile/dialog focus and activation.
- iPad portrait/landscape or split view: Remains inside the existing 520dp
  responsive Account card and scroll view.
- Phone/Web, if in scope: Debug builds use the same responsive flow.

## Accessibility

- Semantics and focus: Text labels describe outcomes; busy and error feedback
  use live-region semantics where appropriate.
- Text scaling and contrast: Reuse theme typography and error colors; rows may
  grow vertically rather than clip.
- Non-gesture alternative: All actions are visible buttons/rows with dialog
  actions.

## UI Acceptance Criteria

- [x] The section remains reachable at compact width and large text scale.
- [x] Confirmation copy distinguishes device-only deletion from cloud data.
- [x] Busy state prevents double execution and identifies the active action.
- [x] Success and error feedback are visible and accessible.

## Verification

- Widget tests: Visibility, cancel, execution, sign-out, busy, and result copy.
- Responsive/semantic/golden tests: Compact-width large-text widget coverage;
  no new golden required.
- Manual device checks: Confirm on iPad Debug build that local files disappear,
  cloud content remains, and subsequent sign-in restores/reconciles normally.

## Implementation Review

- Status: Delivered
- Intentional deviations: None.
