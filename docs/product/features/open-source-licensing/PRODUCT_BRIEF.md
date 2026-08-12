# Open-source Licensing Product Brief

- Status: Foundation delivered; release identity and legal follow-up pending
- Size: Large
- Updated: 2026-08-12
- Roadmap link: Repository governance; outside the feature roadmap

## Problem

InkNest Notes exposes substantial Flutter and Python implementation work but
previously had no root license. Visitors therefore had no affirmative right to
use the code, while the project also lacked an explicit mechanism to require
modified distributed or hosted versions to remain available as source. Brand,
academic material, third-party assets, and future outside contributions also
had no durable licensing boundary.

## Recommended Outcome

Publish the software under `AGPL-3.0-only`, retain the option to negotiate
separate commercial licenses, require a contributor agreement that supports
both editions, license ordinary project documentation under CC BY-SA 4.0, and
reserve InkNest branding and academic materials. Preserve every third-party
component under its original license.

## Scope

- In scope: Flutter and Python software, build and test material, ordinary
  project documentation, contribution terms, commercial-license contact,
  trademarks, bundled font notices, and a dependency-license inventory.
- Non-goals: prohibiting AGPL-compliant commercial use, licensing user-created
  notebook content, granting an actual commercial license, registering a
  trademark, or claiming ownership of third-party dependencies and assets.

## User Flow

1. A visitor reads the root README and follows the applicable license link.
2. A community user may use the software under AGPL; an organization needing
   proprietary terms contacts the copyright holder.
3. A contributor reads and accepts the CLA in the pull-request template before
   the contribution can be accepted.

## Acceptance Criteria

- [x] The repository contains the unmodified AGPLv3 text and clearly declares
  `AGPL-3.0-only` for software.
- [x] Hosted modifications, commercial licensing, documentation, academic
  materials, trademarks, user content, and secrets have explicit boundaries.
- [x] Contributions require a CLA grant supporting AGPL and separately
  licensed official editions.
- [x] Bundled fonts retain their OFL notices and direct software dependencies
  receive a recorded compatibility audit.
- [x] Python package metadata exposes the SPDX license expression.

## Alternatives And Tradeoffs

- MIT, BSD, or Apache-2.0: simpler adoption, but permits proprietary forks and
  therefore does not meet the protection goal.
- Source-available non-commercial license: can prohibit commercial use, but is
  not Open Source under the standard definition and would reduce ecosystem
  compatibility.
- AGPL without separate licensing or a CLA: protects community source but can
  make official app-store or proprietary agreements difficult after accepting
  outside contributions.

## Dependencies And Risks

- License enforcement still requires evidence, copyright ownership, and
  practical follow-up; AGPL cannot prevent independent reimplementation.
- App-store distribution and future proprietary editions require the Project
  Owner to retain sufficient rights in every accepted contribution.
- Dependency licenses must be re-audited before release, especially after new
  native SDKs, fonts, media, or generated assets are introduced.
- The policy and CLA should receive jurisdiction-specific legal review before
  a material commercial transaction or enforcement action.

## Open Decisions

- [ ] Final copyright holder: replace provisional `Lv` with the full personal
  legal name or copyright-owning company and verify employer/school ownership
  does not apply.
- [ ] Final public contact: keep `2256334253@qq.com` or replace it with a
  dedicated licensing address consistently across notices.
- [ ] Brand clearance: search `InkNest` and `InkNest Notes` across relevant
  stores, domains, package registries, and trademark classes before committing
  to the release name.
- [ ] Brand protection: confirm logo/icon provenance and decide whether and
  where to register the cleared word and logo marks.
- [ ] CLA operations: choose a durable acceptance-record system and decide,
  with counsel, when organizational contributors need a separately signed CLA.
- [ ] Network source offer: add a prominent link to the exact corresponding
  source before a modified public server is placed into service.
- [ ] Release review: obtain jurisdiction-specific review of the CLA,
  commercial terms, trademarks, and App Store/Play Store AGPL compatibility;
  repeat dependency and asset auditing for the release build.

## Delivery

- UI/UX spec: Not required; repository governance has no application UI change.
- Implementation status: License foundation delivered; unchecked Open
  Decisions are release-governance work and must remain visible until resolved.
- Verification: License texts, metadata, internal links, font notices,
  dependency declarations, and repository diff checks verified on 2026-08-12.
