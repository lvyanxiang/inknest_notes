# InkNest Cloud Sync And Recovery UI/UX Specification

- Status: Accepted
- Updated: 2026-08-06
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Future sync status panel, conflict detail sheet, Recently
  Deleted list, notebook shelf and Pages panel

## Recommendation

Do not interrupt writing when background synchronization detects a conflict.
Show a persistent, accessible conflict indicator in sync status and label the
recoverable copy without replacing the open notebook. Let the user review the
source device/time and explicitly choose Keep Original, Use Conflict Version,
or Keep Both.

The server slice implements the contract and persistence only. Flutter UI work
must follow this specification in a later slice.

Ordinary deletion should remove the item from its normal library immediately
without implying permanent destruction. A future Recently Deleted entry point
lists active Tombstones and offers Restore. If a concurrent edit races with a
delete, the edit is already preserved by the server; surface a calm sync-status
message rather than a blocking decision dialog.

## User Flow

### First sign-in and library detection

1. After authentication, show a non-destructive checking state while InkNest
   reads local folder/notebook IDs and requests the cloud bootstrap inventory.
2. If both libraries contain content, explain that InkNest found notes on this
   device and in the cloud. Emphasize `合并（推荐）`; do not offer an
   unqualified replace-local action.
3. If only one side contains content, use the same Merge path to upload the
   local-only library or restore the cloud-only library. If both are empty,
   continue directly to the empty library.
4. The comparison uses stable IDs only. Matching titles remain two separate
   notebooks when their IDs differ, and the UI must not imply deduplication by
   name.
5. Cancel, offline, `401`, or server failure returns to the usable local
   library. Retry repeats only the read-only detection request in this slice.

The current slice implements the detection contract and App state model, not
the transfer progress screen or the destructive application of cloud data.

### Conflict recovery

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

### Deletion recovery flow

1. Deleting a notebook, page, or infinite canvas removes it from its normal
   location and confirms that it can be restored from Recently Deleted.
2. Sync receives both the resource delete event and its active Tombstone.
3. Recently Deleted shows the resource type, deletion time, and source device;
   Restore remains available offline as a queued action.
4. A confirmed restore stays busy until the server returns the restored
   Tombstone, then the resource reappears at its prior location as a new
   Revision.
5. When sync reports `delete_conflict`, show “已保留另一台设备上的编辑” in
   sync status. No user choice is required and no editor modal appears.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Pending | Conflict badge, resource label and device/time metadata | Review or dismiss | Conflict remains recoverable |
| Detail | Original and conflict identities plus three outcomes | Keep Original, Use Conflict Version, Keep Both, Cancel | No action is preselected |
| Busy | Selected action with progress; other actions disabled | Cancel only before request starts | Prevent duplicate taps |
| Resolved | Resolution label and completion feedback | Close | Sync updates affected resources |
| Offline/error | Both versions remain locally/cloud recoverable | Retry or close | Explain that no content was discarded |
| Stale resolution | “原版本已再次更新” | Review latest state, Keep Both, or Keep Original | Never overwrite the newer edit |
| Recently deleted | Resource type plus deletion device/time | Restore or close | Full snapshot remains recoverable; no permanent-delete action yet |
| Restoring | Progress on the selected item | Wait | Duplicate taps disabled; failure offers Retry |
| Delete/edit preserved | Non-blocking sync-status message | Review status or dismiss | Edited resource remains active; Tombstone records the automatic resolution |

### First-sign-in state matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Checking | `正在检查此设备和云端笔记…` with progress | Cancel | No library mutation has started |
| Empty | Normal empty-library state | Create a notebook | No sync decision needed |
| Local only | Explain that local notes can be protected in the account | `合并（推荐）`, Later | Later preserves local-only use |
| Cloud only | Explain that cloud notes can be restored to this device | `合并（推荐）`, Later | Later leaves the current local state unchanged |
| Local + cloud | Show both library counts and the no-overwrite promise | `合并（推荐）`, Later | Same titles with different IDs remain separate |
| Offline/error | Explain that checking could not finish | Retry, Continue offline | Existing local library remains available |
| Authentication expired | Explain that sign-in must be refreshed | Sign in again, Continue offline | Never clear local data or credentials silently |

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

- [ ] First-sign-in detection distinguishes empty, local-only, cloud-only, and
  local-plus-cloud states without modifying the local library.
- [ ] Local-plus-cloud emphasizes `合并（推荐）`, never deduplicates by title,
  and lets the user continue offline without losing local content.

- [ ] A background conflict never blocks or overwrites ongoing local writing.
- [ ] Pending conflicts survive restart and appear consistently on other
  devices after sync.
- [ ] The detail flow supports Keep Original, Use Conflict Version, Keep Both,
  cancellation, offline retry and stale-resolution recovery.
- [ ] Notebook/page labels follow the accepted naming while device/time remain
  metadata.
- [ ] Portrait, landscape, compact width, keyboard focus and semantic labels
  are verified.
- [ ] Recently Deleted lists active Tombstones and restores one item without
  blocking writing or implying a retention period that the service has not set.
- [ ] A delete-versus-edit result explains that the edit was preserved and
  never asks the user to choose between deleting and keeping it.

## Verification

- Widget tests: pending list, all resolution actions, retry and stale states.
- Responsive/semantic tests: compact, regular iPad portrait and landscape;
  focus order and screen-reader labels.
- Manual device checks: conflict arrival while drawing and offline recovery on
  a real iPad.

## Implementation Review

- Status: First-sign-in detection contract and Flutter state model delivered;
  visible first-sign-in screens are not wired yet. Conflict and Tombstone
  server contracts are delivered; their Flutter UI is not started.
- Intentional deviations: The server reserves the copy ID immediately but only
  materializes a normal notebook/page when the user chooses Keep Both. This
  avoids temporary duplicate library entries while preserving both snapshots.
