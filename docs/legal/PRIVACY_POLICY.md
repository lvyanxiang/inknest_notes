# InkNest Notes Privacy Policy

- Version: `2026-09-07.1`
- Effective date: September 7, 2026
- Product: InkNest Notes
- Operator: Individual developer Lv
- Contact email: `2256334253@qq.com`

This policy reflects the current functionality of InkNest Notes and explains how we process personal information and user content. Publication and App offline-copy consistency must follow the [legal document publication contract](README.md). Before public release, the operator name and contact details must be verified against the legal identity used in the app stores and reviewed for each release territory.

## 1. Scope and Local-First Principle

InkNest Notes is a local-first digital note-taking app. You can create and edit notebooks, handwriting, text, and shapes; import PDFs or images; record audio; and export documents without registering an account. When you are signed out, InkNest Notes does not upload this note content to InkNest Cloud.

Cross-device cloud synchronization is available only after you register and sign in to a cloud account. You may continue using local features without an account, but cloud synchronization, cloud recovery, and device-session management require one.

## 2. Information We Process

### 2.1 Local Notes and Files

The app stores notebook and folder names, page order, handwriting strokes and their coordinates and timestamps, text boxes, shapes, bookmarks, page templates and dimensions, infinite-canvas content, imported PDFs and images, audio recordings, editing state, and local mappings and pending operations required for synchronization in the app directory on your device.

This information stays on your device by default. Content within the synchronization scope is transferred to InkNest Cloud only after you choose to sign in and use synchronization.

### 2.2 Account and Authentication Information

When you create a cloud account, we process your email address, a secure hash of your password, the Privacy Policy and Terms versions you accepted, and the acceptance time. We do not store a readable plaintext password.

After sign-in, the app also processes access and refresh tokens, an account ID, and session expiration times. Tokens are stored in system-provided secure storage such as Apple Keychain or Android encrypted storage.

### 2.3 Device and Security Information

To distinguish synchronized devices, reuse the same app installation, and manage sessions, we process a randomly generated installation identifier, a user-visible device name, device platform, device records, recent activity time, and revocation status. The installation identifier is not an advertising identifier and is not used for cross-app tracking.

Login rate limiting temporarily processes an irreversible digest of the network IP address in memory to limit repeated failed login attempts; the default window is five minutes. The service produces operational logs such as request ID, method, API path, response status, processing time, and error type. The current service does not create advertising profiles or a log database that analyzes note content.

### 2.4 Cloud Synchronization Content

After you sign in and enable synchronization, we process folder, notebook, page, and infinite-canvas structure and content; PDF, image, and audio attachments; content versions and digests; synchronization cursors; deletion and revision records; and conflict copies. We process this information to upload, download, merge, restore, and resolve conflicts across your devices.

Notes may contain personal or sensitive information that you enter. We do not ask you to provide sensitive information in notes and do not use note content for advertising. You decide whether to record or synchronize such content.

## 3. Device Permissions and Your Choices

- Microphone: Requested only when you start audio recording, to create an audio file attached to a note. Denying permission does not affect features unrelated to recording.
- File access: The system file picker gives the app access only to PDFs, images, or files that you choose to import and export locations that you select. InkNest Notes does not scan files you did not select.
- Network: Used for registration, sign-in, agreement-version checks, cloud synchronization, attachment transfers, and downloading handwriting-recognition models.

If you choose to save an exported file to a third-party file provider or cloud drive, subsequent processing is also governed by that recipient's terms and privacy rules.

## 4. On-Device Handwriting Recognition

Smart Ink uses Google ML Kit Digital Ink Recognition. Handwriting and recognition results are processed on your device. Google states that recognition input and output are not sent to Google servers.

ML Kit uses the network to download the selected language model and may contact Google for model updates, bug fixes, and hardware compatibility information. It may also send metrics such as API performance, usage, and configured languages to Google for diagnostics, maintenance, improvement, and abuse prevention. Google processes these SDK metrics under its privacy terms. When you do not use handwriting recognition, InkNest Notes does not submit handwriting for this feature.

## 5. Purposes of Processing

We process information only to provide local note and file management; create accounts and authenticate users; maintain and protect device sessions; provide cloud synchronization, recovery, versioning, and conflict handling; respond to account or data-deletion requests; diagnose failures, secure APIs, and prevent abuse; and comply with applicable law and app-store requirements.

We do not sell personal information, use note content for advertising, or use advertising identifiers for cross-app tracking. If we later add advertising, analytics, crash reporting, collaboration, or another feature that changes these purposes, we will first update this policy and the in-app explanation and obtain consent again where legally required.

## 6. Sharing, Service Providers, and Third-Party Components

We do not provide your account or note content to unrelated third parties except when you choose to export it, when required by law, or when necessary to provide the product.

The current cloud service uses an operator-configured database and private object storage to process accounts, synchronization metadata, and attachments. The public HTTPS policy will identify the cloud host, storage provider, processing regions, and contact information used in production. A development environment must not be operated as a public production service before those details are published and the required contractual and security reviews are complete.

The app includes Google ML Kit handwriting recognition; its processing is described in Section 4. Operating-system file pickers, secure storage, audio, and media capabilities are provided by Apple, Google, or the device manufacturer. We require service providers to process data only under our instructions and to apply protections no weaker than those described here.

## 7. Storage, Security, and International Transfers

Local data is stored in the app directory on your device. Account tokens and the installation identifier are stored in system secure storage. Cloud metadata is stored in an access-controlled database and attachments in private object storage. Downloads and uploads use short-lived, account-scoped authorized URLs. Passwords are hashed with Argon2, access tokens are short-lived, and only refresh-token digests are stored by the service, with rotation and revocation support.

A public production service must use HTTPS and disclose storage locations and possible international transfers based on the final deployment regions. Local development addresses and credentials in the repository must not be used for a public service.

Although we take reasonable measures, no storage or transmission method can guarantee absolute security. If we discover a security incident that may affect your rights, we will respond and provide notice as required by applicable law.

## 8. Retention

- Local notes: Retained until you delete them in the app, clear app data, or they are removed by device or system storage mechanisms. Signing out of a cloud account does not delete local notes.
- Cloud account and synchronized content: Retained while the account exists. Ordinary deletion may retain recoverable revisions, Tombstones, or conflict records until content is restored or replaced, or the entire cloud account is deleted. We currently do not promise a fixed automatic physical-deletion period after an ordinary note deletion.
- Sessions: Access tokens are valid for 15 minutes by default and refresh tokens for 30 days. Revoked or expired session records may be retained while the account exists for session security and replay protection and are deleted with the account.
- Temporary uploads: Upload sessions expire after 24 hours by default. Cleanup gives expired staging files a default 24-hour waiting period and unreferenced objects a default seven-day quarantine before checking and deleting them. Service failures and retries may delay completion.
- Request logs: The service outputs operational logs without note bodies and does not maintain a separate long-term log database. A production deployment must set the shortest retention needed for security and troubleshooting and disclose the specific period in the public policy.
- Account-deletion retry records: If object cleanup is incomplete, we retain only the account ID, remaining object keys, attempt count, and error type. After completion, we retain a completion record without the email address or note content.

Where required by law or necessary to resolve disputes or protect security, we may restrict processing within the necessary scope and period and disclose applicable exceptions in the public version.

## 9. Your Rights and Controls

You can edit or delete local content, deny microphone permission, avoid registering an account, sign out of the current cloud session, change your password, view signed-in devices and agreement versions, or verify your password and permanently delete the cloud account and associated cloud data under Account → Danger Zone → Delete Account.

Deleting a cloud account immediately disables it and revokes all device sessions, then deletes account database records and account-scoped object-storage files. Temporary storage failures enter a minimal retry queue. This action does not delete local notes already stored on the current device; you may delete them separately on the device.

To request access, correction, a copy, restriction of processing, withdrawal of consent, make a complaint, or ask about other personal-information rights, email `2256334253@qq.com`. To protect the account, we may need to verify the requester's relationship to it. Withdrawing consent does not affect processing that occurred before withdrawal. If processing is required for cloud synchronization, you may continue using local features after withdrawal but cannot continue using the corresponding cloud features.

## 10. Children

InkNest Notes is intended for general learning and note-taking and is not directed specifically to children under 14. A user below the applicable age of independent consent should use an account and cloud synchronization only after a guardian has read and accepted this policy and the Terms of Service. A guardian who believes we processed a minor's information without appropriate consent may contact us to request review and deletion.

## 11. Policy Updates

We may update this policy when features, data processing, laws, or store policies change. For material changes to processing purposes, methods, information categories, or recipients, we will publish a new version and require you to review and explicitly accept it in the app before continuing to use the related cloud features. Published prior versions should remain available at immutable, versioned HTTPS addresses.

## 12. Contact Us

Data controller/operator: Individual developer Lv<br>
Product: InkNest Notes<br>
Contact email: `2256334253@qq.com`

We will review and respond within a reasonable period after receiving an email. At public release, the operator name above must match the legal identity displayed in App Store Connect, Google Play Console, and the public website.

