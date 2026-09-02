# InkNest Cloud Sync And Recovery UI/UX Specification

- Status: Accepted
- Updated: 2026-08-31
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Sync status panel, conflict detail sheet, Recently
  Deleted list, notebook shelf and Pages panel

## Recommendation

Do not interrupt writing when background synchronization detects a conflict.
Show a persistent, accessible conflict indicator in sync status and label the
recoverable copy without replacing the open notebook. Let the user review the
source device/time and explicitly choose Keep Original, Use Conflict Version,
or Keep Both.

The Flutter library now implements the non-blocking status entry, conflict
recovery, and supported Recently Deleted recovery described here.

Use the same warning entry for structural conflicts, but present only the two
meaningful outcomes: `使用本机版本` and `使用云端版本`. Page order, folder
name, notebook organization, page paper/rotation/size, and canvas background
cannot simultaneously coexist on one resource, so the content-only `两个都保留`
action must not appear for these records.

Ordinary deletion should remove the item from its normal library immediately
without implying permanent destruction. A future Recently Deleted entry point
lists active Tombstones and offers Restore. If a concurrent edit races with a
delete, the edit is already preserved by the server; surface a calm sync-status
message rather than a blocking decision dialog.

## User Flow

### First sign-in and library detection

1. After authentication, keep the library usable and show the normal header
   synchronization spinner while InkNest reads local stable IDs and requests
   the cloud bootstrap inventory. Do not open a dialog.
2. If both libraries contain content, execute the conservative Merge path in
   the background. It must not offer or perform an unqualified replace-local
   action.
3. If only one side contains content, upload the local-only library or restore
   the cloud-only library automatically. If both are empty, settle directly to
   the synchronized empty-library state.
4. The comparison uses stable IDs only. Matching titles remain two separate
   notebooks when their IDs differ, and the UI must not imply deduplication by
   name.
5. Offline, `401`, server failure, incompatible structure, or unsupported
   content stops safely, leaves the local library usable, and exposes Retry
   through sync status. No automatic modal or SnackBar appears.

The App implements verified, rollback-safe cloud restore, local upload, and
mixed shared-Revision coordination as one non-blocking automatic flow. A mixed
Merge persists conflict response details before advancing its Cursor, so the
warning badge always opens a real recoverable conflict record.

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

### Automatic Merge semantics

- After detection, the App derives upload, download, and shared-reconciliation
  actions deterministically before it starts Merge. Planning must not create a
  delete or replace-local action.
- Local-only and cloud-only IDs are independent items even when their visible
  names match. Shared IDs are labelled as requiring safe synchronization; the
  preview must not promise that either device's copy will overwrite the other.
- Mixed execution coordinates shared content first, then transfers independent
  resources. A safety-gate failure explains in sync status that no uncertain
  content was overwritten and offers Retry while local use continues.

### Background incremental synchronization

1. After an existing signed-in session becomes active, InkNest first uploads
   persisted page, bookmark/notebook-content, notebook title/archive/existing-
   folder placement, and safe infinite-canvas edits,
   then checks the saved Cursor and downloads available change pages without
   covering the library or editor.
2. A successful upload updates the header state silently. A safe additive or
   existing-resource download refreshes repository-derived library state and
   settles the header to synchronized without showing a dialog or SnackBar.
   Counts remain available by opening sync status.
3. A shared-resource update, delete, conflict, Tombstone, or local pending
   upload keeps the local library and Cursor unchanged and shows a calm
   “需要协调” message.
4. Network or parsing failure preserves the frozen upload batch and returns
   immediately to local use with a cloud-off/error icon and retryable status;
   it never blocks writing or raises an automatic SnackBar.
5. A local edit containing a new attachment remains durably queued while
   InkNest uploads and verifies the attachment before submitting its content.
   Failure uses the existing non-blocking Retry state and never claims that an
   incomplete attachment is synchronized. Existing folder creation/rename
   and deletion use the same background status and retry flow without new
   controls. Deleting a folder retains its existing confirmation, moves its
   notebooks to the library root, and never appears in Recently Deleted. Page
   structure and canvas background use their existing controls and the same
   non-blocking sync status; no new editor control or modal is added.
6. Local saves request a debounced background cycle. Returning the App to the
   foreground and a lightweight foreground interval also request a cycle, so
   another device's changes can arrive without leaving and reopening the
   library. Requests received while a cycle is busy produce one follow-up
   cycle rather than being discarded.
   While the editor is open, the cycle uploads local work but waits to apply
   remote changes until the user returns to the library, avoiding a race with
   the currently open in-memory page or canvas.
7. While signed in, the library header always exposes the existing sync-status
   target. Its sheet includes `立即同步`; activating it closes the sheet and
   starts the same non-blocking push-then-pull path. Signed-out users do not see
   the target. Automatic checks do not show a modal or steal editor focus.

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

### Structural conflict recovery

1. A concurrent metadata commit returns the affected resource and fields.
   InkNest persists the reconciliation item before changing the header to
   “需要处理”; it never opens a dialog automatically.
2. The warning list identifies the resource and summarizes the changed fields,
   such as page order, notebook title, page template/rotation, folder name, or
   canvas background.
3. The detail sheet shows the common baseline, current local value, and current
   cloud value. Values may use concise human labels; raw JSON is not shown.
4. `使用本机版本` retries the local intent against the latest cloud baseline.
   `使用云端版本` discards only that frozen structural intent and applies the
   verified cloud value locally. Both actions require confirmation because one
   structure becomes authoritative.
5. Offline, stale, or repeated conflict leaves the item visible with Retry.
   Content and attachments remain available regardless of the choice.

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
| Structural conflict | Warning badge, resource and changed-field summary | Review or close | Local operation and cloud baseline are both retained |
| Structural detail | Baseline, local value, cloud value | Use Local Version, Use Cloud Version, Cancel | No implicit default; Keep Both is omitted |
| Structural resolution busy | Selected action with progress | Wait | Duplicate taps disabled; failure keeps the item |

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
| Checking | Header synchronization spinner; library remains usable | Continue local work | No destructive library mutation starts |
| Empty | Normal empty-library state | Create a notebook | No sync decision needed |
| Local only | Header synchronization spinner | Continue local work | Upload and verification run automatically |
| Cloud only | Header synchronization spinner | Continue local work | Staged restore applies atomically |
| Local + cloud | Header synchronization spinner | Continue local work | Stable-ID Merge preserves uncertain divergence |
| Offline/error | Cloud-off/error icon and status detail | Retry, Continue locally | Existing local library remains available |
| Authentication expired | Cloud-off/error icon and status detail | Sign in again, Continue locally | Never clear local data or credentials silently |
| Incremental pull applied | Refreshed shelf and synchronized icon | Continue using library | Cursor advances after complete application; no automatic SnackBar |
| Pull needs reconciliation | Existing local shelf plus non-blocking message | Continue locally | Cursor and local files remain unchanged |
| Pull offline/error | Existing local shelf plus retry-later message | Continue locally | No first-sign-in modal or local mutation |
| Signed-in idle | Sync-status target and concise ready message | `立即同步`, Close | Manual request starts non-blocking synchronization |
| Automatic request while busy | Existing syncing state | Continue local work | One follow-up cycle runs after the active cycle |

## Layout And Components

- Placement and hierarchy: sync status owns the entry point; notebook shelf
  and Pages panel may show a small conflict badge but must not add permanent
  editor toolbar controls.
- The existing library-header sync target remains visible whenever an account
  is signed in. It retains a minimum 44 logical-pixel target, tooltip, and
  semantic label; no editor toolbar control is added.
- Reused components: current status/conflict sheets, list rows, progress
  indicators, theme colors and spacing. Dialogs remain only for explicit
  destructive/conflict-replacement confirmation; SnackBars remain only for
  user-initiated operation results.
- New pattern: one conflict detail row that clearly separates the resource
  label from device/time metadata.
- User-facing copy:
  - Notebook: `<原名称>（冲突副本）`.
  - Untitled page: `第 N 页（冲突副本）`.
  - Outcomes: `保留原版本`, `使用冲突版本`, `两个都保留`.
  - Keep Original and Use Conflict Version require a concise confirmation;
    Keep Both is the safest emphasized action.
  - Structural outcomes: `使用本机版本`, `使用云端版本`.
  - Structural field labels: `名称`, `标题`, `归档状态`, `所在文件夹`,
    `页面顺序`, `纸张模板`, `页面方向`, `页面尺寸`, `坐标版本`, `画布背景`.
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
- [x] Local-plus-cloud runs the conservative Merge without a blocking dialog,
  never deduplicates by title, and lets the user continue using local content.
- [x] The App can derive deterministic upload, download, and shared-ID
  reconciliation counts without exposing a delete or replace-local action.
- [x] An initialized session downloads additive cloud-only notebooks in the
  background, refreshes the shelf, and keeps local use available on failure.
- [x] Local persistence, foreground resume, and the foreground recovery
  interval request serialized synchronization without blocking local editing.
- [x] A request received during synchronization produces one follow-up cycle,
  and the signed-in status sheet provides an accessible `立即同步` action.
- [x] Routine automatic synchronization and first-sign-in Merge use header
  status only; they do not open a dialog or automatic SnackBar.

- [x] A background conflict never blocks or overwrites ongoing local writing.
- [x] Pending conflicts survive restart and appear consistently on other
  devices after sync.
- [x] The detail flow supports Keep Original, Use Conflict Version, Keep Both,
  cancellation, offline retry and stale-resolution recovery.
- [x] Folder/notebook/page/canvas metadata conflicts survive restart, open from
  the same warning entry, show baseline/local/cloud summaries, and support Use
  Local Version or Use Cloud Version without offering Keep Both.
- [x] Notebook/page labels follow the accepted naming while device/time remain
  metadata.
- [ ] Portrait, landscape, compact width, keyboard focus and semantic labels
  are verified.
- [x] Recently Deleted lists active Tombstones and restores one item without
  blocking writing or implying a retention period that the service has not set.
- [x] A delete-versus-edit result explains that the edit was preserved and
  never asks the user to choose between deleting and keeping it.

## Verification

- Widget tests: pending list, all resolution actions, retry and stale states.
- Automatic scheduling tests: local debounce, editor-safe upload-only behavior,
  foreground resume, foreground interval, busy-cycle follow-up, and Sync Now.
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
  remain blocked. Remote whole-notebook Tombstones now remove the item from the
  shelf after preserving a local recovery copy and announce that result. A local
  mapped whole-notebook delete now uploads immediately, confirms cross-device
  removal when online, and reports durable automatic retry when offline.
  Any page except the notebook's final remaining page now queues and applies
  deletion across devices, with a calm startup confirmation and a preserved
  recovery position. Restoring it from Recently Deleted returns it to the
  original page number. Pending conflicts
  now survive restart and appear through a badged library-header entry. The
  detail flow shows original/copy identity and source metadata, emphasizes
  `两个都保留`, confirms replacement choices, disables duplicate submission,
  preserves both snapshots on stale/offline errors, and clears the badge only
  after the resulting resource changes apply locally. Active notebook and safe
  trailing-page Tombstones now survive restart and appear through a badged
  Recently Deleted sheet with type, deletion time, source device, and Restore.
  Restore disables duplicate submission and removes the row only after the
  resource reappears locally; errors retain the row for retry. Existing
  move-left/move-right actions in Pages now also synchronize their resulting
  full page order without adding controls or blocking editing. A remote order
  appears through the normal refreshed Pages panel; a concurrent stale order
  uses the existing non-blocking sync failure/retry state. The existing canvas
  background picker now synchronizes blank, dotted, and grid choices; accepted
  remote backgrounds appear when the canvas refreshes, while a concurrent
  background change uses the same non-blocking failed/retry state. Each infinite-
  canvas notebook owns one Canvas, so deleting it uses the existing shelf
  notebook deletion and Notebook Tombstone flow; no standalone child-Canvas
  entry point is added. The library header now also shows syncing,
  completed, needs-attention, failed, and edit-preserved states. Its sheet
  reports durable failed-operation counts and provides Retry; retry reuses the
  frozen idempotent batch. A `delete_conflict` is presented as a calm successful
  preservation outcome with no resolution action. After a successful
  new-device restore, the next App start goes directly to ordinary background
  sync instead of repeating the first-sign-in Merge dialog; an incomplete
  handoff remains retryable and never claims incremental initialization.
  The existing restore/Merge failure state now reflects a full local recovery
  boundary rather than only staged-file cleanup: if final mapping, metadata, or
  Cursor persistence fails, the shelf and device sync state are restored to
  their pre-operation contents before Retry or Continue Offline is offered.
  Existing shelf Rename, Archive/Restore, and Move actions now also queue
  notebook metadata without adding new controls. A remote accepted update
  appears through the normal refreshed shelf; a true concurrent same-field
  change uses the existing non-blocking sync failure/retry state while both the
  local shelf value and frozen operation remain intact.
  Existing New Folder and Rename actions now also queue folder metadata. A new
  or renamed folder appears on another device through the normal shelf refresh;
  a concurrent rename uses the same non-blocking failed/retry status and keeps
  the local operation. Existing Delete Folder uses the same flow: remote devices
  remove the folder and show its notebooks at the root, with concise sync-status
  feedback and no additional shelf control.
  New pages added, duplicated, or imported into an already synchronized notebook
  now upload in the background with stable IDs, referenced assets, and the final
  full page order. Page paper, rotation, dimensions, and coordinate-space metadata
  follow the same Revision-guarded flow as page content. Concurrent structural
  changes persist as a warning-badge item; its detail shows baseline, local, and
  cloud summaries and offers only `使用本机版本` or `使用云端版本` because one
  resource cannot safely keep two active orders or metadata sets.
  Successful local persistence now requests a two-second debounced cycle;
  foreground resume and a 30-second foreground recovery interval use the same
  serialized scheduler. Requests arriving while busy produce one follow-up
  cycle. An editor-covered library uploads local work but defers remote apply
  until the library is current. Signed-in users always have the existing cloud
  status target and can start `立即同步` from its sheet.
- Intentional deviations: The server reserves the copy ID immediately but only
  materializes a normal notebook/page when the user chooses Keep Both. This
  avoids temporary duplicate library entries while preserving both snapshots.
