# InkNest Notes Release Readiness Checklist

- Status: **NO-GO — not ready for public App Store or Google Play release**
- First audit: 2026-08-26
- Last updated: 2026-08-31
- Release direction: iPadOS/iOS first; Android remains in the same checklist
- Scope: public binary release with the current optional account and cloud-sync
  features visible

This file is the source of truth for store-release readiness. Update an item
only after the implementation and its evidence are both present. Keep
`docs/development/STATUS.md` as the short resume pointer rather than copying
this checklist into it.

## Status Rules

- `[ ]` means incomplete or not yet verified.
- `[x]` means completed and verified for the release candidate.
- Add the completion date and concise evidence under an item when checking it.
- Reopen an item if a dependency, policy, certificate, store declaration, or
  release build changes in a way that invalidates its evidence.
- Change the top-level status to **GO** only after every Store Blocker is
  checked and every Internal Release Gate is either checked or explicitly
  accepted by the product owner with a dated note.

## Store Blockers

### Application identity, branding, and signing

- [ ] **REL-001 — Choose the final application identity.**
  - Replace `com.example.inknestnotes` with the permanent iOS Bundle ID and
    Android application ID/namespace.
  - Update test target identifiers where applicable.
  - Evidence: App Store Connect and Play Console records match the committed
    identifiers.
- [ ] **REL-002 — Replace Flutter template branding.**
  - Supply the final owned logo, iOS AppIcon set, Android adaptive/legacy icons,
    and launch experience.
  - Remove the Flutter default icon and verify every required size.
  - Evidence: icon asset review plus screenshots from installed release builds.
- [ ] **REL-003 — Configure production Android signing.**
  - Remove the release build's debug signing configuration.
  - Create and securely retain the upload key; enable or document Play App
    Signing and recovery ownership.
  - Evidence: release AAB certificate is not `CN=Android Debug`.
- [ ] **REL-004 — Produce a clean Android release App Bundle.**
  - Install Android SDK command-line tools and accept required licenses.
  - Resolve the native debug-symbol stripping failure.
  - Use a reliable Flutter artifact source; the configured China mirror
    returned invalid POM files during the 2026-08-26 audit.
  - Evidence: `flutter build appbundle --release` exits successfully from a
    clean environment and the AAB passes Play Console pre-review.
- [ ] **REL-005 — Produce and upload a signed iOS archive.**
  - Confirm Apple Developer team, distribution certificate, provisioning, and
    App Store Connect application record.
  - Evidence: signed archive validates and uploads successfully to TestFlight.

### Production service and account lifecycle

- [ ] **REL-006 — Configure a real production API origin.**
  - The committed fallback is `http://127.0.0.1:8000`; a release without an
    explicit Dart define embeds that development endpoint.
  - Select the production region, domain, TLS configuration, and release-time
    configuration mechanism.
  - Evidence: signed release builds connect only to the intended HTTPS service
    and retain offline/local-first behavior during an outage.
- [ ] **REL-007 — Complete production backend operations.**
  - Decide PostgreSQL and object-storage topology, backups, restore drills,
    secrets, migrations, monitoring, alerts, security scanning, CORS, rate
    limits, upload limits, and incident ownership.
  - Evidence: production runbook, health checks, backup/restore drill, and
    monitored staging soak test.
- [ ] **REL-008 — Implement account deletion and data deletion.**
  - Add a discoverable in-app deletion path with reauthentication and clear
    confirmation.
  - Delete or explicitly retain, under a documented lawful policy, account,
    device, token, notebook, revision, tombstone, conflict, and object-storage
    data.
  - Provide a public web deletion/request page for Google Play and users who no
    longer have the App installed.
  - Evidence: end-to-end tests plus App Store/Play Console deletion URLs.
  - 2026-08-31 implementation evidence: the App now provides reauthenticated,
    two-stage deletion; the API deactivates the user, revokes all sessions,
    deletes cascaded account rows and `users/{user_id}/` objects, and persists
    retryable cleanup when object deletion fails. Unit/widget tests cover
    completion, failed-storage retry, and local-note retention. This item stays
    open until the public HTTPS deletion/request page and console URLs exist.

### Privacy, legal, and store policy

- [ ] **REL-009 — Publish the privacy policy and terms.**
  - Make the privacy policy available inside the App and at a public,
    non-geofenced HTML URL.
  - Cover email/account data, installation/device identity, notebook content,
    PDFs, images, audio, cloud storage, logs, retention, deletion, service
    providers, security, and contact details.
  - Add service terms/EULA appropriate to the release model.
  - Use one canonical artifact for each document/version. Generate the HTTPS
    rendering and App offline fallback from it; do not maintain separate text.
  - Make the App prefer the matching immutable HTTPS version online and use
    only the same-version/content-digest bundled copy offline. Block acceptance
    if the displayed content cannot be proven to match the advertised version.
  - 2026-08-31 implementation evidence: versioned acceptance and in-App readers
    are implemented. Local version `2026-08-31.1` now accurately covers the
    current App/backend data, permissions, ML Kit SDK metrics, retention,
    deletion, open-source terms, and present individual-developer contact,
    without legal-text placeholders. This item stays open until the store legal
    identity is confirmed, production processor/region and log-retention facts
    are added, counsel review is complete, and stable public HTTPS documents
    are live.
  - Publishing contract and future URL structure:
    `docs/legal/README.md`.
- [ ] **REL-010 — Complete platform privacy declarations.**
  - Add and validate the App-owned iOS `PrivacyInfo.xcprivacy`, including
    collected-data and required-reason API declarations that apply to the App.
  - Audit all native SDK privacy manifests.
  - Complete App Store privacy labels and Google Play Data Safety declarations
    from the exact release dependency set.
  - Confirm microphone permission copy and denial/retry behavior match actual
    audio recording behavior.
- [ ] **REL-011 — Finalize legal identity and brand clearance.**
  - Replace provisional copyright holder `Lv` and confirm the permanent legal
    and support contacts.
  - Complete `InkNest` / `InkNest Notes` name, store, domain, package, and
    trademark clearance.
  - Confirm ownership/provenance of logo, icons, screenshots, illustrations,
    fonts, and generated assets.
- [ ] **REL-012 — Complete release license review.**
  - Regenerate dependency and asset license inventories for the release build.
  - Review AGPL/App Store/Play Store compatibility, CLA operation, trademark
    policy, and commercial licensing for the intended jurisdiction.
  - If a public modified InkNest server is operated, expose a prominent link
    to the exact corresponding source and retain that source by deployed
    version.

### Store submission material

- [ ] **REL-013 — Prepare App Store product metadata.**
  - Final name, subtitle, description, keywords, category, age rating, release
    notes, copyright, support URL, privacy URL, reviewer notes, and a working
    review account when cloud behavior is reviewed.
- [ ] **REL-014 — Prepare Apple screenshots and review evidence.**
  - Capture required iPhone and iPad sizes from the release candidate.
  - Show the library, handwriting/Pencil workflow, PDF annotation, mixed notes,
    export, and optional account/sync behavior without placeholder data or
    third-party rights issues.
- [ ] **REL-015 — Prepare Google Play listing and policy forms.**
  - Final description, graphics, screenshots, category, content rating, target
    audience, ads declaration, Data Safety, privacy URL, and account-deletion
    URL.
  - Evidence: all Play Console App content sections are complete with no policy
    warnings.

## Internal Release Gates

These are product-safety and quality gates. They may not always trigger an
automatic store rejection, but InkNest should not publicly promise reliable
note taking while they remain unassessed.

### Data protection and recovery

- [ ] **REL-101 — Add an editable notebook/library archive and verified restore.**
  - Define a versioned archive manifest, file list, sizes, and SHA-256 checks.
  - Restore through staging and verification without damaging the existing
    local library on corrupt or interrupted input.
- [ ] **REL-102 — Complete independent backend backup and restore drills.**
  - Back up PostgreSQL and object storage independently and demonstrate a
    complete restore into a separate environment.
- [ ] **REL-103 — Make local persistence crash-safe.**
  - Use temporary files and atomic replacement, define storage migrations, and
    verify interrupted saves cannot destroy the last valid notebook/page.
- [ ] **REL-104 — Define trash retention and permanent deletion behavior.**
  - Reconcile local notebook deletion, cloud Tombstones, retention period,
    restore, permanent deletion, and account deletion into one understandable
    policy.

### Real-device and release-candidate QA

- [ ] **REL-105 — Validate Smart Ink on physical iOS and Android devices.**
  - Test representative Chinese and English handwriting, first-use model
    download, offline behavior after download, accuracy, latency, cancellation,
    and failure recovery.
- [ ] **REL-106 — Complete physical iPad editor QA.**
  - Apple Pencil latency, palm rejection, rotation, Split View, Stage Manager,
    operation handles, keyboard, 200% text, and reduced motion.
- [ ] **REL-107 — Complete document and media stress QA.**
  - Large PDFs, long audio, dense handwriting pages, many-page notebooks, low
    storage, interrupted import/export, weak network, and concurrent sync.
- [ ] **REL-108 — Complete automated release coverage.**
  - Golden editor tests, storage migration tests, PDF export snapshots, large
    notebook performance tests, and release smoke tests.
- [ ] **REL-109 — Fix the MinIO cleanup integration-test isolation/statistics failure.**
  - The 2026-08-26 run reported two eligible staging objects when the test
    expected one; determine whether global cleanup scope or test database
    isolation is incorrect.
  - Evidence: the complete backend integration suite passes repeatedly from a
    clean and a reused local environment.
- [ ] **REL-110 — Add production observability and support workflow.**
  - Crash/error reporting, privacy-safe server metrics and logs, alert routing,
    user support contact, incident triage, and rollback procedure.
- [ ] **REL-111 — Close accessibility gaps.**
  - Audit important controls for labels, focus order, tap targets, contrast,
    Dynamic Type/text scaling, keyboard access, and screen readers.
- [ ] **REL-112 — Decide release languages and localize accordingly.**
  - The current UI is primarily English. Record whether the first release is
    English-only or includes Simplified Chinese, then align App and store text.

## Verified Baseline

- [x] **BASE-001 — Flutter static analysis passes.**
  - 2026-08-26: `flutter analyze` completed with no issues.
- [x] **BASE-002 — Flutter automated tests pass.**
  - 2026-08-26: all 269 tests passed.
- [x] **BASE-003 — Backend formatting, linting, and type checks pass.**
  - 2026-08-26: Ruff formatting/check and mypy passed.
- [x] **BASE-004 — Backend non-integration tests pass.**
  - 2026-08-26: 66 tests passed; 16 integration tests were deselected.
- [x] **BASE-005 — Local PostgreSQL and MinIO services are healthy.**
  - 2026-08-26: `docker compose config --quiet` passed and both services were
    healthy.
- [x] **BASE-006 — iOS device release code compiles without signing.**
  - 2026-08-26: `flutter build ios --release --no-codesign` produced an arm64
    `Runner.app` of approximately 80.7 MB.
  - This does not satisfy REL-005 signing, archive validation, or upload.
- [x] **BASE-007 — Android target SDK is current for the audit date.**
  - Flutter 3.44.4 supplies compile/target SDK 36. Recheck Google Play policy at
    the actual submission date.
- [ ] **BASE-008 — Complete backend integration suite passes.**
  - 2026-08-26: 15 passed and 1 failed in
    `test_asset_cleanup_tracks_and_deletes_real_minio_objects`.
- [ ] **BASE-009 — Android release build completes successfully.**
  - 2026-08-26: dependency resolution succeeded through the official Flutter
    artifact source, but the build exited unsuccessfully while stripping debug
    symbols. The generated AAB remained debug-signed and is not a release
    candidate.
- [x] **BASE-010 — Foreground cloud-sync scheduling is verified.**
  - 2026-08-26: local persistence uses a two-second debounce; App resume and a
    30-second foreground interval request synchronization; busy requests run a
    follow-up cycle; editor-covered operation uploads without applying remote
    files; the signed-in status sheet provides Sync Now.
  - Evidence: 28 focused Flutter synchronization tests, the complete 274-test
    Flutter suite, `flutter analyze`, and `git diff --check` pass.
- [x] **BASE-011 — Signed-out mapped changes catch up safely.**
  - 2026-08-26: sign-out still performs no network synchronization. Successful
    local changes to previously mapped pages, notebooks, folders, and infinite
    canvases persist account/device-scoped intent; matching re-login rebuilds
    the existing Revision-guarded operations, while explicit deletes retain
    their delete semantics and unrelated accounts cannot consume the intent.
  - Evidence: 26 focused Flutter synchronization tests, the complete 279-test
    Flutter suite, `flutter analyze`, and `git diff --check` pass.
- [x] **BASE-012 — Automatic synchronization is non-blocking and conflict-safe.**
  - 2026-08-31: first-sign-in/new-device Merge runs behind library header
    status without an automatic dialog; routine push, pull, deletion, and
    failure feedback no longer raises automatic SnackBars. Mixed-Merge conflict
    payloads are persisted before Cursor advancement and remain reachable from
    the warning badge and three-choice resolution flow.
  - Evidence: 42 focused Flutter synchronization tests, the complete 279-test
    Flutter suite, `flutter analyze`, and `git diff --check` pass.
- [x] **BASE-013 — Initialized-notebook P0 synchronization is complete.**
  - 2026-08-31: inserted, duplicated, and PDF-imported child pages upload with
    stable IDs, verified assets, and final page order; page template, rotation,
    dimensions, and coordinate-space metadata use Revision-guarded explicit
    metadata; folder/notebook/page/canvas structural conflicts persist behind
    the warning badge and support an explicit local-or-cloud resolution.
  - Evidence: 134 focused synchronization tests, the complete 285-test Flutter
    suite, `flutter analyze`, backend Ruff/mypy, and all 67 backend unit tests
    pass. PostgreSQL/MinIO integration execution remains to be repeated when
    the local Docker daemon is available; no schema migration was introduced.

## Conditional Market Checks

- [ ] **REL-201 — Confirm launch territories and jurisdiction-specific duties.**
  - Recheck privacy, consumer, encryption, content, tax, developer identity,
    and application-filing requirements for every selected territory.
  - If distributing in mainland China, maintain a separate verified checklist
    for the applicable application filing, developer identity, network service,
    and content requirements before enabling that storefront.

## Release Decision Record

| Date | Decision | Reason | Owner |
| --- | --- | --- | --- |
| 2026-08-26 | NO-GO | Store identity/signing, privacy/account deletion, production service, legal review, store material, and release QA remain incomplete. | Project owner |

## Update Log

| Date | Item | Change | Evidence |
| --- | --- | --- | --- |
| 2026-08-26 | Initial audit | Created the release-readiness source of truth and recorded the verified baseline. | Repository/configuration audit plus Flutter, backend, iOS, and Android checks described above. |
| 2026-08-26 | BASE-010 | Added and verified foreground automatic synchronization scheduling and Sync Now. | 28 focused Flutter tests plus static analysis. |
| 2026-08-26 | BASE-011 | Added restart-safe, account-scoped catch-up for mapped changes made while signed out. | 26 focused and 279 complete Flutter tests plus static analysis. |
| 2026-08-31 | BASE-012 | Removed automatic synchronization dialogs/SnackBars and preserved first-Merge conflict details for the warning-badge flow. | 42 focused and 279 complete Flutter tests plus static analysis. |
| 2026-08-31 | BASE-013 | Completed incremental child-page creation, explicit page metadata, and persistent user-resolvable structural conflicts. | 134 focused and 285 complete Flutter tests, static analysis, and 67 backend unit tests; integration environment unavailable. |

## Policy References

Revalidate these references at submission time because store policies change:

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play target API requirements](https://developer.android.com/google/play/requirements/target-sdk)
