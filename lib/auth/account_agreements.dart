const currentPrivacyPolicyVersion = '2026-09-07.1';
const currentTermsVersion = '2026-09-07.1';
const currentAgreementEffectiveDate = 'September 7, 2026';

enum AccountLegalDocumentType { privacyPolicy, termsOfService }

class AccountLegalSection {
  const AccountLegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

class AccountLegalDocument {
  const AccountLegalDocument({
    required this.type,
    required this.title,
    required this.version,
    required this.sections,
  });

  final AccountLegalDocumentType type;
  final String title;
  final String version;
  final List<AccountLegalSection> sections;
}

const privacyPolicyDocument = AccountLegalDocument(
  type: AccountLegalDocumentType.privacyPolicy,
  title: 'InkNest Notes Privacy Policy',
  version: currentPrivacyPolicyVersion,
  sections: [
    AccountLegalSection(
      'Operator and Contact Information',
      'InkNest Notes is provided and operated by the individual developer Lv. Contact email: 2256334253@qq.com.'
          '\n\nThis policy reflects the current functionality of InkNest Notes and explains how we process personal information and user content. Before public release, the operator name and contact details must be verified against the legal identity used in the app stores and reviewed for each release territory.',
    ),
    AccountLegalSection(
      '1. Scope and Local-First Principle',
      'InkNest Notes is a local-first digital note-taking app. You can create and edit notebooks, handwriting, text, and shapes; import PDFs or images; record audio; and export documents without registering an account. When you are signed out, InkNest Notes does not upload this note content to InkNest Cloud.'
          '\n\nCross-device cloud synchronization is available only after you register and sign in to a cloud account. You may continue using local features without an account, but cloud synchronization, cloud recovery, and device-session management require one.',
    ),
    AccountLegalSection(
      '2. Information We Process',
      'Local notes and files: The app stores notebook and folder names, page order, handwriting strokes and their coordinates and timestamps, text boxes, shapes, bookmarks, page templates and dimensions, infinite-canvas content, imported PDFs and images, audio recordings, editing state, and local mappings and pending operations required for synchronization in the app directory on your device. This information stays on your device by default. Content within the synchronization scope is transferred to InkNest Cloud only after you choose to sign in and use synchronization.'
          '\n\nAccount and authentication information: When you create a cloud account, we process your email address, a secure hash of your password, the Privacy Policy and Terms versions you accepted, and the acceptance time. We do not store a readable plaintext password. After sign-in, the app also processes access and refresh tokens, an account ID, and session expiration times. Tokens are stored in system-provided secure storage such as Apple Keychain or Android encrypted storage.'
          '\n\nDevice and security information: To distinguish synchronized devices, reuse the same app installation, and manage sessions, we process a randomly generated installation identifier, a user-visible device name, device platform, device records, recent activity time, and revocation status. The installation identifier is not an advertising identifier and is not used for cross-app tracking. Login rate limiting temporarily processes an irreversible digest of the network IP address in memory to limit repeated failed login attempts; the default window is five minutes. The service produces operational logs such as request ID, method, API path, response status, processing time, and error type. The current service does not create advertising profiles or a log database that analyzes note content.'
          '\n\nCloud synchronization content: After you sign in and enable synchronization, we process folder, notebook, page, and infinite-canvas structure and content; PDF, image, and audio attachments; content versions and digests; synchronization cursors; deletion and revision records; and conflict copies. We process this information to upload, download, merge, restore, and resolve conflicts across your devices. Notes may contain personal or sensitive information that you enter. We do not ask you to provide such information and do not use note content for advertising.',
    ),
    AccountLegalSection(
      '3. Device Permissions and Your Choices',
      'Microphone: Requested only when you start audio recording, to create an audio file attached to a note. Denying permission does not affect features unrelated to recording.'
          '\n\nFile access: The system file picker gives the app access only to PDFs, images, or files that you choose to import and export locations that you select. InkNest Notes does not scan files you did not select.'
          '\n\nNetwork: Used for registration, sign-in, agreement-version checks, cloud synchronization, attachment transfers, and downloading handwriting-recognition models.'
          '\n\nIf you choose to save an exported file to a third-party file provider or cloud drive, subsequent processing is also governed by that recipient’s terms and privacy rules.',
    ),
    AccountLegalSection(
      '4. On-Device Handwriting Recognition',
      'Smart Ink uses Google ML Kit Digital Ink Recognition. Handwriting and recognition results are processed on your device. Google states that recognition input and output are not sent to Google servers.'
          '\n\nML Kit uses the network to download the selected language model and may contact Google for model updates, bug fixes, and hardware compatibility information. It may also send metrics such as API performance, usage, and configured languages to Google for diagnostics, maintenance, improvement, and abuse prevention. Google processes these SDK metrics under its privacy terms. When you do not use handwriting recognition, InkNest Notes does not submit handwriting for this feature.',
    ),
    AccountLegalSection(
      '5. Purposes of Processing',
      'We process information only to provide local note and file management; create accounts and authenticate users; maintain and protect device sessions; provide cloud synchronization, recovery, versioning, and conflict handling; respond to account or data-deletion requests; diagnose failures, secure APIs, and prevent abuse; and comply with applicable law and app-store requirements.'
          '\n\nWe do not sell personal information, use note content for advertising, or use advertising identifiers for cross-app tracking. If we later add advertising, analytics, crash reporting, collaboration, or another feature that changes these purposes, we will first update this policy and the in-app explanation and obtain consent again where legally required.',
    ),
    AccountLegalSection(
      '6. Sharing, Service Providers, and Third-Party Components',
      'We do not provide your account or note content to unrelated third parties except when you choose to export it, when required by law, or when necessary to provide the product.'
          '\n\nThe current cloud service uses an operator-configured database and private object storage to process accounts, synchronization metadata, and attachments. The public HTTPS policy will identify the cloud host, storage provider, processing regions, and contact information used in production. A development environment must not be operated as a public production service before those details are published and the required contractual and security reviews are complete.'
          '\n\nThe app includes Google ML Kit handwriting recognition; its processing is described in Section 4. Operating-system file pickers, secure storage, audio, and media capabilities are provided by Apple, Google, or the device manufacturer. We require service providers to process data only under our instructions and to apply protections no weaker than those described here.',
    ),
    AccountLegalSection(
      '7. Storage, Security, and International Transfers',
      'Local data is stored in the app directory on your device. Account tokens and the installation identifier are stored in system secure storage. Cloud metadata is stored in an access-controlled database and attachments in private object storage. Downloads and uploads use short-lived, account-scoped authorized URLs. Passwords are hashed with Argon2, access tokens are short-lived, and only refresh-token digests are stored by the service, with rotation and revocation support.'
          '\n\nA public production service must use HTTPS and disclose storage locations and possible international transfers based on the final deployment regions. Local development addresses and credentials in the repository must not be used for a public service. Although we take reasonable measures, no storage or transmission method can guarantee absolute security.',
    ),
    AccountLegalSection(
      '8. Retention',
      'Local notes: Retained until you delete them in the app, clear app data, or they are removed by device or system storage mechanisms. Signing out of a cloud account does not delete local notes.'
          '\n\nCloud account and synchronized content: Retained while the account exists. Ordinary deletion may retain recoverable revisions, Tombstones, or conflict records until content is restored or replaced, or the entire cloud account is deleted. We currently do not promise a fixed automatic physical-deletion period after an ordinary note deletion.'
          '\n\nSessions: Access tokens are valid for 15 minutes by default and refresh tokens for 30 days. Revoked or expired session records may be retained while the account exists for session security and replay protection and are deleted with the account.'
          '\n\nTemporary uploads: Upload sessions expire after 24 hours by default. Cleanup gives expired staging files a default 24-hour waiting period and unreferenced objects a default seven-day quarantine before checking and deleting them. Service failures and retries may delay completion.'
          '\n\nRequest logs: The service outputs operational logs without note bodies and does not maintain a separate long-term log database. A production deployment must set the shortest retention needed for security and troubleshooting and disclose the specific period in the public policy.'
          '\n\nAccount-deletion retry records: If object cleanup is incomplete, we retain only the account ID, remaining object keys, attempt count, and error type. After completion, we retain a completion record without the email address or note content. Where required by law or necessary to resolve disputes or protect security, we may restrict processing within the necessary scope and period.',
    ),
    AccountLegalSection(
      '9. Your Rights and Controls',
      'You can edit or delete local content, deny microphone permission, avoid registering an account, sign out of the current cloud session, change your password, view signed-in devices and agreement versions, or verify your password and permanently delete the cloud account and associated cloud data under Account → Danger Zone → Delete Account.'
          '\n\nDeleting a cloud account immediately disables it and revokes all device sessions, then deletes account database records and account-scoped object-storage files. Temporary storage failures enter a minimal retry queue. This action does not delete local notes already stored on the current device; you may delete them separately on the device.'
          '\n\nTo request access, correction, a copy, restriction of processing, withdrawal of consent, make a complaint, or ask about other personal-information rights, email 2256334253@qq.com. To protect the account, we may need to verify the requester’s relationship to it. Withdrawing consent does not affect processing that occurred before withdrawal. If processing is required for cloud synchronization, you may continue using local features after withdrawal but cannot continue using the corresponding cloud features.',
    ),
    AccountLegalSection(
      '10. Children',
      'InkNest Notes is intended for general learning and note-taking and is not directed specifically to children under 14. A user below the applicable age of independent consent should use an account and cloud synchronization only after a guardian has read and accepted this policy and the Terms of Service. A guardian who believes we processed a minor’s information without appropriate consent may contact us to request review and deletion.',
    ),
    AccountLegalSection(
      '11. Policy Updates',
      'We may update this policy when features, data processing, laws, or store policies change. For material changes to processing purposes, methods, information categories, or recipients, we will publish a new version and require you to review and explicitly accept it in the app before continuing to use the related cloud features. Published prior versions should remain available at immutable, versioned HTTPS addresses.',
    ),
    AccountLegalSection(
      '12. Contact Us',
      'Data controller/operator: Individual developer Lv\nProduct: InkNest Notes\nContact email: 2256334253@qq.com'
          '\n\nWe will review and respond within a reasonable period after receiving an email. At public release, the operator name above must match the legal identity displayed in App Store Connect, Google Play Console, and the public website.',
    ),
  ],
);

const termsOfServiceDocument = AccountLegalDocument(
  type: AccountLegalDocumentType.termsOfService,
  title: 'InkNest Notes Terms of Service',
  version: currentTermsVersion,
  sections: [
    AccountLegalSection(
      'Service Provider and Contact Information',
      'InkNest Notes is provided by the individual developer Lv. Contact email: 2256334253@qq.com.'
          '\n\nThese Terms reflect the current functionality of InkNest Notes. Before public release, the service-provider name and contact details must be verified against the legal identity used in the app stores and reviewed for each release territory.',
    ),
    AccountLegalSection(
      '1. Formation and Acceptance',
      'Welcome to InkNest Notes. By registering a cloud account, selecting acceptance, or continuing to use cloud services that require these Terms, you confirm that you have read, understood, and accepted these Terms and the matching version of the InkNest Notes Privacy Policy. If you do not agree, you may avoid registering and continue using local note features that do not require a cloud account.'
          '\n\nIf you are below the legal age to accept these Terms independently in your region, a guardian must read and accept them before you use an account and cloud synchronization. If you use the service for an organization, you confirm that you have authority to bind that organization to these Terms.',
    ),
    AccountLegalSection(
      '2. Service',
      'InkNest Notes provides local notebooks, handwriting and text editing, shapes, PDF and image import, audio notes, infinite canvases, bookmarks, export, and optional accounts and cross-device cloud synchronization. Available functionality is determined by the current app version.'
          '\n\nWhen you are signed out, core note features run locally on the device. Registration and sign-in support cloud synchronization, cloud recovery, and session and device management. Cloud synchronization uses a local-first merge process that may create conflict copies requiring your choice.',
    ),
    AccountLegalSection(
      '3. Registration and Account Security',
      'You must register with a valid email address that you are authorized to use, protect your password and devices, and take responsibility for activity under your account. The current version does not yet provide email verification or email-based password recovery, so keep your password safe. You can change it on a signed-in device by providing the current password.'
          '\n\nIf you suspect unauthorized account use, promptly change your password, revoke other devices, or contact 2256334253@qq.com. To protect accounts and the service, we may limit unusual sign-ins, revoke sessions, or temporarily block clear abuse.',
    ),
    AccountLegalSection(
      '4. Your Content and License',
      'You retain the rights provided by law in notes, handwriting, text, PDFs, images, recordings, and other content that you create or lawfully import. You confirm that you have the right to use and upload this content and that it does not infringe another person’s copyright, privacy, personal-information rights, or other legal rights.'
          '\n\nTo provide local processing, synchronization, downloading, recovery, conflict handling, and deletion as you choose, we need to copy, store, transmit, reformat, and process the relevant content while the service is operating. You grant only the non-exclusive technical license necessary for those functions. It does not transfer ownership or permit us to use note content for advertising. After account deletion is complete, this cloud-processing license ends with deletion of the related cloud data; content retained locally on the current device remains under your control.',
    ),
    AccountLegalSection(
      '5. Software License and Open-Source Components',
      'InkNest Notes source code is currently available under the GNU Affero General Public License v3 only (AGPL-3.0-only). Some fonts, dependencies, and third-party components have their own licenses. These Terms primarily govern the official app, cloud service, accounts, and brand use and do not limit rights expressly granted by an open-source license.'
          '\n\nMaking the software open source does not automatically grant permission to use the InkNest or InkNest Notes names, logos, or other brand elements for counterfeit or confusing products. The project trademark and licensing documents govern those uses.',
    ),
    AccountLegalSection(
      '6. Acceptable Use',
      'You must not use InkNest Notes to violate another person’s rights, upload content you are not authorized to use, distribute malicious code, bypass authentication or access controls, probe or attack the service, interfere with other users, abuse APIs at scale, impersonate another person, or engage in activity that violates applicable law.'
          '\n\nFor suspected unlawful, infringing, or security-threatening activity, we may limit cloud services, revoke sessions, preserve security records, or cooperate with authorities as reasonably necessary and permitted by law. Except for urgent security or legal requirements, we will provide a reason and a practical appeal or contact channel where possible.',
    ),
    AccountLegalSection(
      '7. Cloud Synchronization, Backup, and Data Safety',
      'We take reasonable measures to maintain cloud synchronization, but networks, devices, third-party systems, and software can experience interruption, delay, conflict, or data corruption. Synchronization is not an absolute guarantee that data can never be lost.'
          '\n\nRegularly export important notes and keep an independent copy. Confirm content state before deleting data, migrating devices, installing test builds, or resolving conflicts. When local and cloud edits conflict, the app may preserve both versions and ask you to keep the local version, cloud version, or both.',
    ),
    AccountLegalSection(
      '8. Third-Party Services and Exports',
      'Handwriting recognition uses on-device Google ML Kit capabilities and may download models and send SDK performance and usage metrics. See the Privacy Policy for details. The operating system provides file selection, secure storage, audio, and media capabilities.'
          '\n\nWhen you choose to export a file to a system share target, third-party cloud drive, or another app, that recipient is responsible for its service and its own terms apply. Unless we expressly state otherwise, a third-party service is not sponsored, endorsed, or partnered with InkNest Notes.',
    ),
    AccountLegalSection(
      '9. Fees and Subscriptions',
      'The current version does not offer paid subscriptions, in-app purchases, or automatic renewal. If paid features are introduced later, we will clearly show the price, billing period, benefits, cancellation, and refund rules before purchase and update these Terms as needed. These Terms alone do not authorize us to charge you.',
    ),
    AccountLegalSection(
      '10. Changes, Interruptions, and Termination',
      'We may update the app and cloud service to fix issues, improve security, comply with law, or improve the product. Material feature or agreement changes will be communicated through reasonable methods such as an in-app version notice. Development, maintenance, network failures, force majeure, or third-party infrastructure issues may cause temporary interruption.'
          '\n\nYou may stop using the service, sign out, or request cloud-account deletion at any time. If we discontinue a public cloud service, we will provide advance notice and reasonable export or data-handling instructions where feasible and legally required.',
    ),
    AccountLegalSection(
      '11. Account and Cloud-Data Deletion',
      'Under Account → Danger Zone → Delete Account, you can enter your current password and the confirmation text DELETE to permanently delete the cloud account and associated cloud data. After the request is accepted, the account is immediately disabled, all device sessions are revoked, and database records and account-scoped object-storage files are deleted. Temporary failures enter a retry process.'
          '\n\nCloud-account deletion cannot be undone, but it does not automatically delete local notes already stored on the current device. You must delete local content separately on the device. Before public launch, we will also provide a public web entry point that can initiate a request without reinstalling the app.',
    ),
    AccountLegalSection(
      '12. Disclaimers and Limitation of Liability',
      'To the extent permitted by law, the service is provided in its current state and we use reasonable efforts to maintain functionality and security, but we do not promise uninterrupted or error-free operation, fitness for every particular purpose, or recovery of all data. Consumer rights, liability for personal injury, and liability arising from intent or gross negligence that cannot legally be excluded are not limited by this section.'
          '\n\nTo the extent permitted by law, liability will be determined under applicable law with regard to foreseeability, actual loss, each party’s fault, and whether the user took reasonable backup measures. These Terms do not exclude or restrict essential rights granted to you by law.',
    ),
    AccountLegalSection(
      '13. Governing Law and Dispute Resolution',
      'These Terms are governed by laws that are binding on the service provider and you. If a dispute arises, first contact us at 2256334253@qq.com to seek a negotiated resolution. If it cannot be resolved, you may pursue your rights before a court or dispute-resolution body with jurisdiction under applicable law. Before public release, we will add any regional terms required for the actual operator and release territories.',
    ),
    AccountLegalSection(
      '14. Updates and General Terms',
      'When features, law, or the service model changes materially, we will publish a new version and require explicit acceptance before you continue using the related cloud features. Prior versions should remain available at versioned addresses.'
          '\n\nIf any provision is found invalid, the remaining provisions continue in effect. A delay in exercising a right does not waive it. You may not transfer a cloud account unless permitted by applicable law or these Terms. If the service provider changes, we will give legally required notice and handle the related rights and obligations.',
    ),
    AccountLegalSection(
      '15. Contact Us',
      'Service provider: Individual developer Lv\nProduct: InkNest Notes\nContact email: 2256334253@qq.com'
          '\n\nAt public release, the service-provider name above must match the legal identity displayed in App Store Connect, Google Play Console, and the public website.',
    ),
  ],
);
