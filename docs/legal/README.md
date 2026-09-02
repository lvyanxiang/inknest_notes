# InkNest Legal Document Publishing Contract

The current local legal text is maintained in `PRIVACY_POLICY.md` and
`TERMS_OF_SERVICE.md`. It describes the repository's current behavior and uses
the project's present individual-developer identity and contact. Before public
release, that identity must be reconciled with the store account, production
processors/regions and counsel review. When the production HTTPS site is
available, InkNest must publish and consume one canonical legal document set;
the website and App must not be maintained as independent copies.

## Required URL Structure

- Current Privacy Policy: `https://<production-domain>/legal/privacy`
- Current Terms of Service: `https://<production-domain>/legal/terms`
- Account deletion request: `https://<production-domain>/account-deletion`
- Immutable versioned documents:
  - `https://<production-domain>/legal/privacy/<version>`
  - `https://<production-domain>/legal/terms/<version>`

The production domain remains undecided. Privacy, Terms, and account deletion
may share one domain and deployment, but they remain distinct discoverable
routes.

## Single-Source Rule

1. Each Privacy Policy and Terms version has exactly one canonical source
   artifact. Until the publishing pipeline exists, the Markdown documents in
   this directory are the review sources and `lib/auth/account_agreements.dart`
   is their matching App rendering.
2. The HTTPS document and App offline document are generated from that same
   artifact. Do not copy-edit either rendered output separately.
3. Each artifact carries a version and deterministic content digest. The
   backend's current version, the HTTPS version, and the bundled App fallback
   must match before a release is accepted.
4. Published versioned URLs are immutable. A material edit creates a new
   version and requires explicit user acceptance.
5. The unversioned current URLs may redirect to or render the newest immutable
   version.

## App Loading Contract

- Online: load the HTTPS document matching the agreement version the App is
  presenting for acceptance.
- Offline or temporarily unreachable: show only the bundled local copy of that
  exact version.
- Never silently substitute a local copy with a different version or content
  digest.
- If neither an exact remote document nor its exact bundled copy is available,
  do not collect acceptance; show a retryable availability error instead.
- The legal reader must identify the displayed version and whether it is the
  offline copy. Previously accepted versions remain auditable through their
  immutable HTTPS URLs.

## Release Gate

Before publishing a build:

- finalize legal identity, contact, territories, processors, retention, and
  counsel review;
- publish all required HTTPS routes without authentication or geo-blocking;
- generate the App fallback from the same canonical artifacts;
- verify version and digest equality across canonical source, HTTPS output,
  bundled fallback, and backend agreement constants;
- verify the account-deletion page can initiate a request without requiring
  the App to be installed.
