# Account Release Readiness Product Brief

- Status: Accepted for implementation
- Size: Large
- Updated: 2026-08-31
- Roadmap link: `docs/development/RELEASE_CHECKLIST.md` REL-008 and REL-009

## Problem

InkNest lets a person create a cloud account but does not yet provide the
complete account lifecycle expected before public distribution. Registration
does not record versioned agreement acceptance, signed-in users cannot change
their password or delete the account, and the App has no durable in-product
privacy-policy or terms entry. This leaves users without adequate control over
their identity and cloud data.

## Recommended Outcome

Keep local-first use independent from the account. Require an explicit,
unticked agreement during registration; make the same versioned Privacy Policy
and Terms of Service readable before and after sign-in; allow a signed-in user
to change their password after entering the current password; and let them
request permanent deletion after reauthentication and a destructive
confirmation.

Deletion immediately deactivates the account and revokes every session. The
server records a retryable deletion request, removes all account-prefixed
objects, then hard-deletes the account and all PostgreSQL-owned cloud data.
Local notes on the requesting device remain untouched and become signed-out
local notes.

## Scope

- In scope:
  - Versioned Privacy Policy and Terms of Service acceptance at registration.
  - Agreement status in account responses and an authenticated acceptance
    endpoint for pre-existing accounts that have no recorded consent.
  - In-App agreement readers available while signed out and signed in.
  - Current-password verified password change that revokes other sessions.
  - Current-password verified account deletion request covering PostgreSQL
    account content and all MinIO objects under the account prefix.
  - A retryable server deletion record when object cleanup cannot finish.
  - Clearing cloud credentials after accepted deletion while preserving local
    notebooks.
  - On production HTTPS availability, one canonical artifact per legal
    document/version generates both the public page and the App offline copy.
    The App uses the matching HTTPS document online and the exact bundled copy
    only when the network is unavailable.
- Non-goals:
  - Inventing a final legal identity, support address, governing law, or public
    production URL.
  - Password-reset email and mandatory email verification before an email
    provider is selected.
  - Subscription cancellation because subscriptions are not implemented.
  - Deleting local notes as a side effect of deleting a cloud account.

## User Flow

1. Registration requires the user to open or directly activate Privacy Policy
   and Terms links and tick one explicit agreement checkbox before submission.
2. A signed-in account page exposes Legal, Change password, and Delete account
   below identity/device information.
3. Password change verifies the current password, saves the new password, and
   signs out other devices.
4. Delete account explains cloud versus local consequences, requires the
   current password plus the exact confirmation text `DELETE`, then submits the
   request. Accepted deletion clears this device's cloud session and returns
   the App to local-only use.
5. A temporary cleanup failure remains an accepted server-side deletion
   request; the account stays inactive and an operator retry can complete it.

## Acceptance Criteria

- [x] Registration cannot submit until the current Privacy Policy and Terms
  versions are explicitly accepted, and the server rejects absent or stale
  versions.
- [x] Existing accounts without recorded acceptance can review and accept the
  current documents without losing local notes.
- [x] Privacy Policy and Terms are accessible from both registration and the
  signed-in account page, with version/effective-date information.
- [x] Password change rejects an incorrect current password, validates the new
  password, and revokes sessions on other devices.
- [x] Account deletion requires reauthentication and explicit destructive
  confirmation, revokes every session, and removes or queues removal of all
  account database rows and account-prefixed objects.
- [x] A deletion request never deletes notebooks stored locally on the device.
- [x] Offline/server errors retain the account/session and allow retry before a
  deletion request is accepted.
- [x] Local Privacy Policy and Terms accurately describe the current App,
  backend, permissions, SDKs, retention behavior, account controls, and present
  individual-developer contact without unresolved text placeholders.
- [ ] Production legal publishing uses one canonical source per document and
  version; HTTPS, bundled fallback, backend version, and content digest match.
- [ ] With network access the App displays the matching HTTPS version; without
  network access it displays only the exact same-version local fallback and
  never records acceptance for mismatched or unavailable content.

## Alternatives And Tradeoffs

- Immediate database and object deletion without a request record:
  rejected because PostgreSQL and MinIO do not share a transaction and a
  partial failure could either strand personal data or destroy referenced
  files while leaving an active account.
- Delete local and cloud notes together: rejected because it violates the
  established optional-account, local-first contract.
- Pretend existing accounts accepted the new agreements during migration:
  rejected because inferred consent is not a real user action.
- Maintain the website and App legal text independently: rejected because
  apparently identical copies can drift without a visible version change.

## Dependencies And Risks

- Product or technical dependency: final legal identity, contact address,
  production URLs, territory choice, and email provider remain external
  decisions before public release.
- Data/privacy risk: deletion must cover tokens, devices, notebooks, pages,
  canvases, revisions, conflicts, Tombstones, sync changes/commits, asset rows,
  ready objects, and staging objects. Retry records must not retain note
  content or email after completion.
- Migration risk: existing accounts receive null agreement acceptance and must
  explicitly accept; no consent is backfilled.
- Legal-publication risk: the local text is usable for development and review,
  but production hosting provider/region, log retention, verified store legal
  identity, public URLs, launch territories, and counsel review must be added
  before it becomes the public release version.

## Open Decisions

- Final legal name, support/privacy contact, governing jurisdiction, launch
  territories, and public policy/deletion URLs.
- Email provider and whether public launch requires verified email before sync.
- Production-domain value and the build/publish mechanism that generates both
  HTTPS and bundled renderings from the canonical legal artifacts.

## Delivery

- UI/UX spec: `UI_UX_SPEC.md`.
- Implementation status: account lifecycle App/backend delivered; canonical
  HTTPS publishing and exact offline-fallback generation wait for the
  production domain.
- Verification: current account implementation passed Flutter and backend
  checks on 2026-08-31. The future publishing pipeline must add automated
  version/content-digest equality verification before REL-009 can close.
  Local legal version `2026-08-31.1` was audited against current dependencies,
  permissions, account/sync storage, logging, ML Kit behavior, deletion, and
  licensing records.
