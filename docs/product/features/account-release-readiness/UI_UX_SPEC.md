# Account Release Readiness UI/UX Specification

- Status: Account lifecycle delivered; HTTPS/offline reader update specified
- Updated: 2026-08-31
- Product brief: `PRODUCT_BRIEF.md`
- Affected surfaces: Account screen, registration form, legal document reader,
  password-change dialog, account-deletion dialog

## Recommendation

Keep all rare account administration inside the existing Account screen.
Registration uses one unticked agreement checkbox with separate tappable
Privacy Policy and Terms links. Signed-in users see a Legal section and a
visually separated Danger zone. Password change uses a focused dialog;
account deletion uses a two-stage destructive dialog so an accidental tap can
never submit it.

## User Flow

1. Registration: enter email/password, review either legal document, tick
   agreement, then create the account.
2. Existing account needing acceptance: after sign-in, Account shows a required
   agreement card; cloud use remains unavailable until accepted.
3. Change password: Account → Change password → current/new/confirm → Update.
4. Delete: Account → Delete account → consequence summary → Continue → enter
   password and `DELETE` → Delete account.
5. Success signs out and returns to local-only Account state. Cancel closes the
   dialog with no request. Failure keeps fields and shows an accessible inline
   error.

## State Matrix

| State | Visible UI | Available actions | Feedback/recovery |
|---|---|---|---|
| Registration default | Unticked agreement, legal links | Review, tick, submit | Submit validates agreement |
| Legal reader | Title, version, effective date, sections | Back/Close | No account mutation |
| Legal reader online | HTTPS content for the presented version | Read, Back/Close | Uses the canonical published document |
| Legal reader offline | Bundled content with the exact same version/digest and an offline-copy label | Read, retry, Back/Close | Acceptance remains available only for an exact match |
| Legal content mismatch | Availability error; agreement action unavailable | Retry, Back/Close | Never accepts unseen or different content |
| Password busy | Disabled fields and progress | None | Success message or inline retry |
| Delete first confirmation | Cloud/local consequence summary | Cancel, Continue | No mutation yet |
| Delete final confirmation | Password and `DELETE` field | Cancel, Delete account | Destructive action disabled until exact text |
| Delete accepted | Signed-out local-only account view | Continue using notes | Local notebooks remain |
| Delete error before acceptance | Dialog remains open | Correct/retry/cancel | Account and session remain active |
| Agreement required | Warning card and document links | Review and Accept | Sync stays unavailable until accepted |

## Layout And Components

- Placement and hierarchy: identity and device first; Security; Legal; Sign
  out; separated Danger zone last.
- Reused components: existing Account card, Material dialogs, text fields,
  error container, filled/outlined/text buttons, and semantic error colors.
- New component: a simple read-only legal document page using selectable text.
- The current local reader uses clear Simplified Chinese legal text, Chinese
  section headings, and a visible version/effective date while retaining the
  existing scrollable selectable layout.
- User-facing copy explicitly distinguishes deleting cloud data from retaining
  local notes.
- When production HTTPS is configured, the reader prefers the immutable URL for
  the presented version. Its offline fallback is generated from the same
  canonical artifact and visibly identified as an offline copy; it is not a
  separately authored document.

## Input And Responsive Behavior

- Pencil and touch: standard controls only; no gesture-only action.
- Mouse/trackpad and keyboard: logical focus order; Enter never triggers final
  deletion unless both confirmation fields validate.
- iPad portrait/landscape or split view: reuse the existing scrollable 520px
  account card; dialogs remain scrollable under keyboard and large text.
- Phone/Web: same single-column flow; Web public deletion page is not part of
  this repository slice.

## Accessibility

- Semantics and focus: legal links and destructive buttons have explicit
  labels; errors are live regions; focus moves to the first invalid field.
- Text scaling and contrast: scroll instead of clipping at 200% text; danger
  meaning uses label and icon in addition to color.
- Non-gesture alternative: every action is a button or form control.

## UI Acceptance Criteria

- [x] Registration agreement is explicit, initially off, keyboard reachable,
  and not bundled into the submit button.
- [x] Both legal documents are readable before and after authentication.
- [x] Password change and deletion expose busy, validation, success, failure,
  cancel, and retry states.
- [x] Deletion requires current password and exact `DELETE`, clearly says local
  notes remain, and never offers a one-tap destructive path.
- [x] Compact width and large text do not hide the final actions.
- [ ] Online and offline legal readers display the same version and content
  digest, and a mismatch disables acceptance with a retryable error.

## Verification

- Widget tests: registration consent gating, legal readers, password errors and
  success, deletion cancellation/validation/success/local-note preservation.
- Responsive/semantic tests: 500px width, 150–200% text, button targets and
  live error semantics.
- Manual device checks: keyboard avoidance and VoiceOver/TalkBack reading order.

## Implementation Review

- Status: Passed on 2026-08-31 with Flutter analysis, account widget tests,
  backend lint/type checks, and unit tests.
- Intentional deviations: the public browser deletion page is outside this App
  UI slice and remains tracked by REL-008.
