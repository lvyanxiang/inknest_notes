# InkNest Cloud Conflict Recovery UI/UX Specification

- Status: Accepted
- Updated: 2026-08-06
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Future sync status panel, conflict detail sheet, notebook
  shelf and Pages panel

## Recommendation

Do not interrupt writing when background synchronization detects a conflict.
Show a persistent, accessible conflict indicator in sync status and label the
recoverable copy without replacing the open notebook. Let the user review the
source device/time and explicitly choose Keep Original, Use Conflict Version,
or Keep Both.

The server slice implements the contract and persistence only. Flutter UI work
must follow this specification in a later slice.

## User Flow

1. Background sync receives a `conflict` operation result or change event.
2. InkNest keeps local writing available and shows “1 个冲突待处理” in sync
   status; it does not open a modal over the editor.
3. The user opens the conflict list and selects a page or notebook conflict.
4. A detail sheet shows the original label, conflict label, source device,
   time, and the three explicit outcomes.
5. The selected action stays busy until the server confirms it. Success updates
   the list and announces the result; failure preserves both snapshots and
   offers Retry.
6. The user may close the sheet without resolving. Pending conflicts remain
   visible across restart and other devices.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Pending | Conflict badge, resource label and device/time metadata | Review or dismiss | Conflict remains recoverable |
| Detail | Original and conflict identities plus three outcomes | Keep Original, Use Conflict Version, Keep Both, Cancel | No action is preselected |
| Busy | Selected action with progress; other actions disabled | Cancel only before request starts | Prevent duplicate taps |
| Resolved | Resolution label and completion feedback | Close | Sync updates affected resources |
| Offline/error | Both versions remain locally/cloud recoverable | Retry or close | Explain that no content was discarded |
| Stale resolution | “原版本已再次更新” | Review latest state, Keep Both, or Keep Original | Never overwrite the newer edit |

## Layout And Components

- Placement and hierarchy: sync status owns the entry point; notebook shelf
  and Pages panel may show a small conflict badge but must not add permanent
  editor toolbar controls.
- Reused components: current sheets, dialogs, list rows, progress indicators,
  snackbars, theme colors and spacing.
- New pattern: one conflict detail row that clearly separates the resource
  label from device/time metadata.
- User-facing copy:
  - Notebook: `<原名称>（冲突副本）`.
  - Untitled page: `第 N 页（冲突副本）`.
  - Outcomes: `保留原版本`, `使用冲突版本`, `两个都保留`.
  - Keep Original and Use Conflict Version require a concise confirmation;
    Keep Both is the safest emphasized action.

## Input And Responsive Behavior

- Pencil and touch: all actions use normal 44 logical-pixel targets; the sheet
  never captures canvas drawing gestures behind it.
- Mouse/trackpad and keyboard: rows expose hover/focus, Enter opens details,
  Escape closes without resolving, and focus returns to the invoking row.
- iPad: use a centered or anchored detail sheet in portrait/landscape; compact
  Split View may use a bottom sheet without covering unsaved state.
- Phone/Web: not part of the current server slice; reuse the same labels and
  state model when those clients are implemented.

## Accessibility

- Announce resource type, original name/page number, pending state, source
  device and time separately instead of encoding conflict only by color.
- Keep logical focus order from identity and metadata to the safest action,
  alternatives, then Cancel. Support text scaling without truncating outcomes.
- Every action has a button alternative; no swipe or gesture is required.

## UI Acceptance Criteria

- [ ] A background conflict never blocks or overwrites ongoing local writing.
- [ ] Pending conflicts survive restart and appear consistently on other
  devices after sync.
- [ ] The detail flow supports Keep Original, Use Conflict Version, Keep Both,
  cancellation, offline retry and stale-resolution recovery.
- [ ] Notebook/page labels follow the accepted naming while device/time remain
  metadata.
- [ ] Portrait, landscape, compact width, keyboard focus and semantic labels
  are verified.

## Verification

- Widget tests: pending list, all resolution actions, retry and stale states.
- Responsive/semantic tests: compact, regular iPad portrait and landscape;
  focus order and screen-reader labels.
- Manual device checks: conflict arrival while drawing and offline recovery on
  a real iPad.

## Implementation Review

- Status: Server contract delivered; Flutter UI not started.
- Intentional deviations: The server reserves the copy ID immediately but only
  materializes a normal notebook/page when the user chooses Keep Both. This
  avoids temporary duplicate library entries while preserving both snapshots.
