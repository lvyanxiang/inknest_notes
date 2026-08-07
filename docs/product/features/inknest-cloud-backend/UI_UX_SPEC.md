# InkNest Cloud Sync And Recovery UI/UX Specification

- Status: Accepted
- Updated: 2026-08-07
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

The App now implements the detection dialog and state model. A cloud-only new
device can explicitly confirm a verified, rollback-safe restore, a local-only
device can confirm verified cloud protection, and a mixed library can confirm
the safely gated shared-Revision flow. Incompatible shared structure,
attachments, or unsupported canvas conflicts return to an actionable retry /
continue-local state without overwriting either side.

### Account entry, sign-in, and registration

1. The library remains the startup screen. Its header Account button opens a
   dedicated account page and never blocks access to local notebooks.
2. Signed-out state presents Sign in first and a Create account mode on the
   same page. Both ask for email/password; registration also asks for password
   confirmation.
3. Inline validation keeps invalid requests local. During submission fields and
   mode switching are disabled and the primary action shows progress.
4. Success returns to the library with the Account button representing the
   signed-in identity. Failure stays on the form, preserves the email, clears no
   notebooks, and explains the next action without exposing server internals.
5. Signed-in state shows email and device identity plus Sign out. Sign-out
   returns to the signed-out account page even when server revocation cannot be
   reached; local notes remain untouched.
6. Restoring a saved session never overlays the editor or blocks the library.
   A rejected refresh changes the Account entry to signed out; a temporary
   offline failure keeps the saved identity available for local-only use.

### Merge preview semantics

- After detection, the App derives upload, download, and shared-reconciliation
  counts before the user starts Merge. The eventual confirmation surface may
  summarize these counts, but it must not show an item as deleted or replaced.
- Local-only and cloud-only IDs are independent items even when their visible
  names match. Shared IDs are labelled as requiring safe synchronization; the
  preview must not promise that either device's copy will overwrite the other.
- `合并（推荐）` remains the primary action. `稍后` exits without executing the
  plan, and rebuilding the preview after retry must produce the same ordering.
- The current screen shows these counts after authentication and enables
  `合并（推荐）` for cloud-only restore, local-only upload, and mixed execution.
  Mixed execution coordinates shared content first, then transfers independent
  resources; a safety-gate failure explains that no uncertain content was
  overwritten and offers Retry or local continuation.

### Background incremental synchronization

1. After an existing signed-in session becomes active, InkNest first uploads
   persisted page, bookmark/notebook-content, and safe infinite-canvas edits,
   then checks the saved Cursor and downloads available change pages without
   covering the library or editor.
2. A successful upload announces how many local changes were sent. A safe
   additive download refreshes the shelf and includes cloud changes and
   received notebooks in the same calm confirmation.
   Safe updates to existing content instead report how many existing items were
   updated and refresh repository-derived library state before the confirmation.
3. A shared-resource update, delete, conflict, Tombstone, or local pending
   upload keeps the local library and Cursor unchanged and shows a calm
   “需要协调” message.
4. Network or parsing failure preserves the frozen upload batch and returns
   immediately to local use with a concise retry-later message; it never blocks
   writing.
5. A local edit containing an attachment not yet verified in cloud remains
   local and does not claim upload success. Structural changes unsupported by
   the current content-only contract likewise remain local.

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

### Account state matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Restoring | Library remains usable; Account entry shows compact progress | Open local notebooks | No full-screen startup gate |
| Signed out | Sign-in form and Create account mode | Submit, switch mode, Back | Existing local library remains available |
| Invalid input | Field-level message | Correct input | No network request starts |
| Submitting | Primary action progress; fields disabled | Wait | Duplicate submission prevented |
| Authentication error | Concise form-level message | Retry, edit credentials | Email remains; password is not logged |
| Signed in | Email and current device metadata | Done, Sign out | Account entry reflects identity |
| Offline session | Saved identity plus cloud-unavailable message when needed | Continue locally, Retry later | Credentials and local notes remain |

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
| Merge preview | Upload/download/shared counts and no-overwrite promise | `合并（推荐）`, Later | Planning alone makes no local or cloud changes |
| Incremental pull applied | Refreshed shelf plus snackbar summary | Continue using library | Cursor advances after complete application |
| Pull needs reconciliation | Existing local shelf plus non-blocking message | Continue locally | Cursor and local files remain unchanged |
| Pull offline/error | Existing local shelf plus retry-later message | Continue locally | No first-sign-in modal or local mutation |

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
- Account uses a 44-pixel header target. The account page is a centered card on
  regular iPad widths and a padded single column on compact widths, with a
  maximum readable form width. Password fields provide show/hide controls and
  keyboard submit follows email → password → confirmation/action order.

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

- [x] The library opens without authentication and exposes an accessible
  Account entry at compact and regular widths.
- [x] Sign in and Create account validate fields, disable duplicate submission,
  show safe actionable errors, and return to the unchanged library on success
  or Back.
- [x] A stored session restores without blocking local notes; Sign out removes
  only account state and never clears the local notebook repository.
- [x] Account controls maintain 44-pixel targets, logical keyboard focus, text
  scaling, password obscuring, and semantic labels.

- [x] First-sign-in detection distinguishes empty, local-only, cloud-only, and
  local-plus-cloud states without modifying the local library.
- [x] Local-plus-cloud emphasizes `合并（推荐）`, never deduplicates by title,
  and lets the user continue offline without losing local content.
- [x] The App can derive deterministic upload, download, and shared-ID
  reconciliation counts without exposing a delete or replace-local action.
- [x] An initialized session downloads additive cloud-only notebooks in the
  background, refreshes the shelf, and keeps local use available on failure.

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

- Status: Account UI/session delivery is complete. First-sign-in detection,
  deterministic Merge preview, error/retry states, confirmed cloud-only
  restore, local-only verified upload, and safely gated mixed Merge are wired
  into the signed-in library. Shared-ID content uses server Revision/Content
  Hash outcomes; incompatible structure/assets and divergent canvas content
  remain blocked. Conflict and Tombstone server contracts are delivered; their
  Flutter list/detail UI is not started.
- Intentional deviations: The server reserves the copy ID immediately but only
  materializes a normal notebook/page when the user chooses Keep Both. This
  avoids temporary duplicate library entries while preserving both snapshots.
