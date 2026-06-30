# InkNest Notes Subscription Plan

This is a product draft for future monetization. It should guide product and
architecture decisions, not lock the project into final pricing.

## Product Principle

Keep the core writing experience trustworthy and useful for free. Charge for
cross-device convenience, long-term data safety, cloud storage, and advanced
study features.

Long term, the paid product should also unlock InkNest as a cross-device
knowledge system: iPad for handwriting and PDF study, phone for capture and
review, and Web for a Yuque-like knowledge base.

The cleanest positioning is:

- Free: local-first notes.
- InkNest Cloud: automatic cross-device sync and cloud recovery.
- InkNest Pro: advanced study and productivity features.

## Recommended Launch Structure

Launch with only Free and InkNest Cloud. Add InkNest Pro after search, OCR,
audio, AI, or Web workflows are real enough to justify a higher tier.

### Free

Positioning: local notes for single-device or light users.

Price:

- Free.

Included:

- Local notebooks.
- Basic handwriting tools.
- PDF import and annotation.
- PDF export.
- Manual backup and restore.
- No InkNest account required.

Platform behavior:

- iPadOS / iOS: local storage, plus system/iCloud backup or manual export to
  iCloud Drive where available.
- Android: local storage, plus manual export to Google Drive, OneDrive,
  Dropbox, or local files through the system file picker.
- Web: marketing, account management, and documentation only at first.

Not included:

- InkNest server sync.
- Automatic cross-platform sync.
- Cloud history.
- Cloud conflict recovery.
- Cloud OCR, AI, or audio transcription.

Product note: do not weaken the free writing experience too much. Users need to
trust the app with real notes before they will pay for cloud features.

### InkNest Cloud

Positioning: automatic sync, backup, and recovery across devices.

Draft pricing:

- USD 2.99/month.
- USD 19.99/year or USD 24.99/year.
- China pricing reference: CNY 18/month, CNY 128/year, or CNY 168/year.

Included:

- InkNest account.
- Automatic InkNest Cloud sync.
- iPad, iPhone, Android, Web, and future desktop access under one account.
- Cloud backup.
- Device replacement restore.
- 10 GB cloud storage.
- 30-day version history.
- Conflict detection and conflict copies.
- Web notebook viewing, document organization, download, and basic editing when
  Web is available.
- All Free features.

This should be the first paid product. It directly matches the user's reason to
subscribe: notes are available anywhere and are safer than local-only storage.

### InkNest Pro

Positioning: study and productivity power features.

Draft pricing:

- USD 5.99/month.
- USD 49.99/year or USD 59.99/year.
- China pricing reference: CNY 38/month, CNY 298/year.

Included:

- Everything in InkNest Cloud.
- 100 GB cloud storage.
- Longer version history, such as 180 days.
- Handwriting recognition.
- Full-text search.
- PDF OCR.
- Audio recording sync.
- Audio transcription.
- Web knowledge-base search.
- Web document organization.
- AI summaries.
- AI question answering.
- AI knowledge-base retrieval.
- Flashcards or quiz generation.
- Advanced export options.
- Priority support.

Do not launch this tier until the advanced features are credible. A thin Pro
tier can make the product feel over-monetized.

### Team / Education

Positioning: later-stage collaboration and institution sales.

Draft pricing:

- USD 6-10/user/month.
- USD 60-100/user/year.

Potential features:

- Shared team spaces.
- Shared notebooks.
- Admin console.
- Member management.
- Unified billing.
- Classroom distribution workflows.
- Organization-level retention and support.

This is not an MVP or early post-MVP target.

## Cross-Platform Entitlement Model

Use one InkNest account entitlement across all platforms.

The user may purchase through:

- Apple In-App Purchase on iOS/iPadOS/macOS.
- Google Play Billing on Android.
- Web checkout later, subject to platform policy and app review constraints.

Regardless of purchase channel, the entitlement should unlock the same InkNest
account benefits across supported platforms.

Important product constraint: if the app unlocks digital features inside iOS or
Android apps, expect Apple and Google in-app purchase rules to apply.

## Platform Strategy

### iPadOS / iOS

Free:

- Local storage.
- System/iCloud backup or manual iCloud Drive export where available.

Paid:

- InkNest Cloud sync.
- Account-based restore.
- Cross-platform access.

### Android

Free:

- Local storage.
- Manual backup/export through the Android system file picker.
- Users may save backup files to Google Drive or another storage provider.

Avoid promising iCloud-like automatic sync for free Android users. Android
system backup is useful for device restore, but it should not be positioned as
notebook sync.

Paid:

- InkNest Cloud sync.
- Account-based restore.
- Cross-platform access.

### Web

Free:

- Marketing pages.
- Account and subscription management.
- Documentation.

Paid:

- Cloud notebook viewing.
- Knowledge-base spaces.
- Folder or document hierarchy.
- Markdown or rich-text documents.
- Embedded notebook pages and PDFs.
- Download/export.
- Search across documents and synced notes.
- Sharing links.
- Later: collaborative editing and team spaces.

### Desktop

Mac and Windows can come later. Their main purpose should be reviewing,
organizing, exporting, and light editing before they try to match iPad writing.

## Local Data And Cloud Data Merge Policy

Core rule: never silently overwrite local notes.

When a user signs in on a device that already has local notes, and the account
also has cloud notes, show a merge flow.

Recommended default:

- Merge local and cloud libraries.
- Upload local-only notebooks.
- Download cloud-only notebooks.
- Keep both copies when identity or revision state is unclear.

Suggested sign-in message:

```text
This device has local notebooks, and your InkNest account has cloud notebooks.
InkNest will not delete local notes.
```

Suggested actions:

- Merge local and cloud notebooks. Recommended.
- View cloud notebooks without uploading local notes.
- Keep this device offline.
- Advanced: replace local library with cloud library.

Advanced replacement must require a second confirmation.

## Merge Rules

Use conservative merge behavior first.

- Different notebook IDs: keep both.
- Same title but different IDs: keep both; optionally label the local copy.
- Same notebook ID and only one side changed: accept the changed side.
- Same notebook ID and both sides changed since last sync: create a conflict
  copy.
- Deleted locally but changed in cloud: keep cloud copy and mark a conflict.
- Deleted in cloud but changed locally: keep local copy and mark a conflict.
- Never permanently delete user data during the first sync pass.

For the first real sync version, notebook-level or page-level conflicts are
acceptable. Do not start with stroke-level real-time merging unless the product
requires collaboration.

## Required Sync Metadata Later

When InkNest Cloud begins, models should gain enough metadata for sync and
conflict detection:

- `deviceId`
- `userId`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `revision`
- `lastSyncedRevision`
- `contentHash`
- `syncState`
- `conflictOf`

This metadata should be designed before implementing server sync.

## Recommended Roadmap For Monetization

### Phase 1: Free Product Trust

- Improve handwriting.
- Improve PDF annotation.
- Improve local persistence reliability.
- Add manual backup and restore packages.
- Add library organization.

### Phase 2: InkNest Account Foundation

- Add sign-in.
- Add entitlement model.
- Add local/cloud library merge flow.
- Add server-side notebook storage.

### Phase 3: InkNest Cloud Subscription

- Add automatic upload/download.
- Add restore on new devices.
- Add 30-day version history.
- Add basic Web viewing.

### Phase 4: InkNest Pro

- Add handwriting search.
- Add OCR.
- Add audio sync and transcription.
- Add AI study features.

### Phase 5: Web Knowledge Base

- Add Yuque-like spaces and document hierarchy.
- Add rich text or Markdown editing.
- Embed notebook pages and PDFs into Web documents.
- Add tags, backlinks, references, and sharing links.
- Add knowledge-base search.

### Phase 6: Collaboration And AI Knowledge

- Add team spaces.
- Add collaborative editing and comments.
- Add AI retrieval across notebooks and documents.
- Add AI summaries, question answering, flashcards, and quiz generation.

## Open Product Questions

- Should free users have a notebook count limit, storage limit, or no limit?
- Should iCloud sync be described as a free feature, or only as a system backup
  compatibility note?
- Should Android manual backup use one `.inknestbackup` file per notebook or
  one full-library archive?
- Should Web checkout be offered before or after mobile subscriptions?
- Should Web start as read-only notebook viewing or document editing first?
- Should the Web knowledge-base tier live in InkNest Cloud, InkNest Pro, or a
  later team plan?
- What storage limit is sustainable for the first Cloud tier?
- How much history should Cloud keep before Pro is required?
