import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

void main() {
  test(
    'cloud restore hands a fresh device directly to incremental sync',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-handoff-');
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final cloud = _CloudRestoreHandoffClient();
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final preview = await service.inspect();
      final restored = await service.restoreCloudOnly(
        preview: preview,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(restored.cursorPersisted, isTrue);
      final mappings = await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).load();
      expect(
        mappings.map((item) => item.remoteResourceId),
        containsAll(['cloud-notebook', 'cloud-page']),
      );

      final restarted = ApiFirstSignInSyncService(
        repository: FileNotebookRepository(rootDirectory: root),
        apiClient: cloud,
        rootDirectory: root,
      );
      final push = await restarted.pushIncremental(
        userId: 'user-1',
        deviceId: 'device-1',
      );
      final pull = await restarted.pullIncremental(
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(push.uploadedOperationCount, 0);
      expect(pull.status, IncrementalSyncPullStatus.upToDate);
      expect(cloud.requestedChangeCursors, ['bootstrap-cursor']);
    },
  );

  test(
    'handoff failure never publishes the incremental Cursor early',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-handoff-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final cloud = _CloudRestoreHandoffClient();
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );
      final preview = await service.inspect();
      await Directory(
        '${root.path}/sync/user-1/device-1/resources.json',
      ).create(recursive: true);

      await expectLater(
        service.restoreCloudOnly(
          preview: preview,
          userId: 'user-1',
          deviceId: 'device-1',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await repository.listNotebooks(), isEmpty);
      expect(
        await Directory(
          '${root.path}/sync/user-1/device-1/resources.json',
        ).exists(),
        isTrue,
      );
      expect(
        (await FileSyncStateStore(
          rootDirectory: root,
          userId: 'user-1',
          deviceId: 'device-1',
        ).loadSnapshot()).lastAppliedCursor,
        isNull,
      );
    },
  );

  test(
    'a new server device reconciles restored cloud page IDs without rehashing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-new-device-merge-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final cloud = _CloudRestoreHandoffClient();
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final cloudOnly = await service.inspect();
      await service.restoreCloudOnly(
        preview: cloudOnly,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      final newDevicePreview = await service.inspect();
      final result = await service.mergeMixed(
        preview: newDevicePreview,
        userId: 'user-1',
        deviceId: 'device-2',
      );

      expect(result.uploadedNotebookCount, 0);
      expect(result.downloadedNotebookCount, 0);
      expect(
        cloud.reconciledOperations
            .where((operation) => operation['resourceType'] == 'page')
            .single['resourceId'],
        'cloud-page',
      );
      expect(
        (await FileSyncStateStore(
          rootDirectory: root,
          userId: 'user-1',
          deviceId: 'device-2',
        ).loadSnapshot()).lastAppliedCursor,
        'bootstrap-cursor',
      );
    },
  );

  test(
    'local-only merge uploads structure, page content, and image bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-local-upload-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final notebook = await repository.createNotebook(title: 'Local notes');
      final secondNotebook = await repository.createNotebook(
        title: 'Other local notes',
      );
      final source = File('${root.path}/source.png')
        ..writeAsBytesSync(const [1, 2, 3, 4]);
      final image = await repository.importImage(
        notebook,
        source,
        position: const Offset(20, 30),
        width: 100,
        height: 80,
      );
      await repository.savePage(
        notebook,
        NotePage(
          id: notebook.pageIds.single,
          width: 768,
          height: 1024,
          images: [image],
        ),
      );
      await repository.setPageBookmarked(
        notebook,
        notebook.pageIds.single,
        true,
      );
      final cloud = _FakeFirstSignInCloudClient();
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final preview = await service.inspect();
      final result = await service.uploadLocalOnly(
        preview: preview,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(result.uploadedNotebookCount, 2);
      expect(result.uploadedAssetCount, 1);
      expect(
        cloud.operations.map((item) => item['resourceType']),
        containsAllInOrder(['notebook', 'page', 'notebook', 'page']),
      );
      final pageOperations = cloud.operations
          .where((item) => item['resourceType'] == 'page')
          .toList();
      expect(pageOperations, hasLength(2));
      expect(
        pageOperations.map((item) => item['resourceId']).toSet(),
        hasLength(2),
      );
      expect(
        pageOperations.map((item) => item['resourceId']),
        isNot(contains('page-1')),
      );
      expect(secondNotebook.pageIds.single, 'page-1');
      final notebookOperation = cloud.operations.firstWhere(
        (item) =>
            item['resourceType'] == 'notebook' &&
            item['resourceId'] == notebook.id,
      );
      final notebookContent =
          (notebookOperation['metadata']! as Map<String, Object?>)['content']!
              as Map<String, Object?>;
      expect(notebookContent['bookmarkedPageIds'], [
        pageOperations.firstWhere(
          (item) =>
              (item['metadata']! as Map<String, Object?>)['notebookId'] ==
              notebook.id,
        )['resourceId'],
      ]);
      expect(cloud.uploadedAsset?.relativePath, image.assetPath);
      expect(cloud.uploadedAsset?.sha256, hasLength(64));
      final state = await FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).loadSnapshot();
      expect(state.lastAppliedCursor, 'cursor-complete');
    },
  );

  test(
    'mixed Merge reconciles shared content before upload and restore',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-mixed-merge-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final shared = await repository.createNotebook(title: 'Shared notes');
      final localOnly = await repository.createNotebook(title: 'Local notes');
      final sharedRemotePageId = _remotePageId(
        shared.id,
        shared.pageIds.single,
      );
      final cloud = _MixedFirstSignInCloudClient(
        sharedNotebook: shared,
        sharedRemotePageId: sharedRemotePageId,
      );
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final preview = await service.inspect();
      final result = await service.mergeMixed(
        preview: preview,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(result.uploadedNotebookCount, 1);
      expect(result.downloadedNotebookCount, 1);
      expect(result.preservedConflictCount, 1);
      expect(
        cloud.reconciledOperations.map((item) => item['resourceType']),
        containsAll(['notebook', 'page']),
      );
      expect(
        cloud.reconciledOperations.every((item) => item['baseRevision'] == 0),
        isTrue,
      );
      expect(cloud.uploadedNotebookIds, contains(localOnly.id));
      expect(
        (await repository.listNotebooks()).map((item) => item.id),
        contains('cloud-only'),
      );
      final state = await FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).loadSnapshot();
      expect(state.lastAppliedCursor, 'cursor-complete');
    },
  );

  test(
    'mixed Merge rejects incompatible shared metadata before commit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-mixed-blocked-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final shared = await repository.createNotebook(title: 'Local title');
      final cloud = _MixedFirstSignInCloudClient(
        sharedNotebook: shared,
        sharedRemotePageId: _remotePageId(shared.id, shared.pageIds.single),
        sharedTitleOverride: 'Cloud title',
      );
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final preview = await service.inspect();

      await expectLater(
        service.mergeMixed(
          preview: preview,
          userId: 'user-1',
          deviceId: 'device-1',
        ),
        throwsStateError,
      );
      expect(cloud.reconciledOperations, isEmpty);
      expect(cloud.uploadedNotebookIds, isEmpty);
    },
  );

  test('mixed Merge rolls local state back when final handoff fails', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-mixed-rollback-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final shared = await repository.createNotebook(title: 'Shared notes');
    final localOnly = await repository.createNotebook(title: 'Local notes');
    final cloud = _MixedFirstSignInCloudClient(
      sharedNotebook: shared,
      sharedRemotePageId: _remotePageId(shared.id, shared.pageIds.single),
    );
    final service = ApiFirstSignInSyncService(
      repository: repository,
      apiClient: cloud,
      rootDirectory: root,
    );
    final preview = await service.inspect();
    await Directory(
      '${root.path}/sync/user-1/device-1/resources.json',
    ).create(recursive: true);

    await expectLater(
      service.mergeMixed(
        preview: preview,
        userId: 'user-1',
        deviceId: 'device-1',
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect((await repository.listNotebooks()).map((item) => item.id).toSet(), {
      shared.id,
      localOnly.id,
    });
    expect(
      await Directory(
        '${root.path}/sync/user-1/device-1/resources.json',
      ).exists(),
      isTrue,
    );
  });
}

String _remotePageId(String notebookId, String localPageId) =>
    'page-${sha256.convert(utf8.encode('$notebookId\u0000$localPageId')).toString().substring(0, 40)}';

class _CloudRestoreHandoffClient implements FirstSignInCloudClient {
  final List<String?> requestedChangeCursors = [];
  final List<Map<String, Object?>> reconciledOperations = [];

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    final now = DateTime.utc(2026, 8, 7);
    return CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: const ['cloud-notebook']),
      baseCursor: 'bootstrap-cursor',
      folders: const [],
      notebooks: [
        CloudSyncNotebook(
          id: 'cloud-notebook',
          folderId: null,
          title: 'Cloud notes',
          layoutMode: 'paged',
          isArchived: false,
          revision: 1,
          contentHash: 'a' * 64,
          content: const {},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      pages: [
        CloudSyncPage(
          id: 'cloud-page',
          notebookId: 'cloud-notebook',
          position: 0,
          width: 768,
          height: 1024,
          coordinateSpaceVersion: 1,
          rotationQuarterTurns: 0,
          template: 'blank',
          revision: 1,
          contentHash: 'b' * 64,
          content: const {'strokes': <Object?>[]},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      infiniteCanvases: const [],
      assets: const [],
    );
  }

  @override
  Future<CloudSyncChangePage> listChanges({
    String? cursor,
    int limit = 100,
  }) async {
    requestedChangeCursors.add(cursor);
    return CloudSyncChangePage(
      changes: const [],
      nextCursor: cursor!,
      hasMore: false,
    );
  }

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    reconciledOperations.addAll(operations);
    return SyncContentCommitResult(
      idempotencyKey: idempotencyKey,
      nextCursor: baseCursor,
      results: [
        for (final operation in operations)
          SyncContentCommitOperationResult(
            operationId: operation['operationId']! as String,
            resourceType: operation['resourceType']! as String,
            resourceId: operation['resourceId']! as String,
            revision: 1,
            contentHash: 'a' * 64,
            outcome: 'unchanged',
          ),
      ],
    );
  }

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) => throw UnimplementedError();

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) => throw UnimplementedError();

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) => throw UnimplementedError();

  @override
  Future<void> completeAssetUpload(String uploadId) =>
      throw UnimplementedError();
}

class _MixedFirstSignInCloudClient implements FirstSignInCloudClient {
  _MixedFirstSignInCloudClient({
    required this.sharedNotebook,
    required this.sharedRemotePageId,
    this.sharedTitleOverride,
  });

  final Notebook sharedNotebook;
  final String sharedRemotePageId;
  final String? sharedTitleOverride;
  final List<Map<String, Object?>> reconciledOperations = [];
  final Set<String> uploadedNotebookIds = {};

  @override
  Future<CloudSyncChangePage> listChanges({String? cursor, int limit = 100}) =>
      throw UnimplementedError();

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    final now = DateTime.utc(2026, 8, 7);
    final notebookIds = {
      sharedNotebook.id,
      'cloud-only',
      ...uploadedNotebookIds,
    };
    return CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: notebookIds),
      baseCursor: uploadedNotebookIds.isEmpty
          ? 'cursor-preview'
          : 'cursor-complete',
      folders: const [],
      notebooks: [
        CloudSyncNotebook(
          id: sharedNotebook.id,
          folderId: null,
          title: sharedTitleOverride ?? sharedNotebook.title,
          layoutMode: 'paged',
          isArchived: false,
          revision: 1,
          contentHash: 'a' * 64,
          content: const {},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
        CloudSyncNotebook(
          id: 'cloud-only',
          folderId: null,
          title: 'Cloud notes',
          layoutMode: 'paged',
          isArchived: false,
          revision: 1,
          contentHash: 'b' * 64,
          content: const {},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      pages: [
        CloudSyncPage(
          id: sharedRemotePageId,
          notebookId: sharedNotebook.id,
          position: 0,
          width: 768,
          height: 1024,
          coordinateSpaceVersion: 1,
          rotationQuarterTurns: 0,
          template: 'blank',
          revision: 1,
          contentHash: 'c' * 64,
          content: const {'strokes': <Object?>[]},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
        CloudSyncPage(
          id: 'cloud-page',
          notebookId: 'cloud-only',
          position: 0,
          width: 768,
          height: 1024,
          coordinateSpaceVersion: 1,
          rotationQuarterTurns: 0,
          template: 'blank',
          revision: 1,
          contentHash: 'd' * 64,
          content: const {'strokes': <Object?>[]},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      infiniteCanvases: const [],
      assets: const [],
    );
  }

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    reconciledOperations.addAll(operations);
    return SyncContentCommitResult(
      idempotencyKey: idempotencyKey,
      nextCursor: 'cursor-reconciled',
      results: [
        for (final operation in operations)
          SyncContentCommitOperationResult(
            operationId: operation['operationId']! as String,
            resourceType: operation['resourceType']! as String,
            resourceId: operation['resourceId']! as String,
            revision: 1,
            contentHash: 'e' * 64,
            outcome: operation['resourceType'] == 'page'
                ? 'conflict'
                : 'unchanged',
          ),
      ],
    );
  }

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    uploadedNotebookIds.addAll(
      operations
          .where((item) => item['resourceType'] == 'notebook')
          .map((item) => item['resourceId']! as String),
    );
    return const SyncMergeCommitResult(nextCursor: 'cursor-uploaded');
  }

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) => throw UnimplementedError();

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) => throw UnimplementedError();

  @override
  Future<void> completeAssetUpload(String uploadId) =>
      throw UnimplementedError();

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();
}

class _FakeFirstSignInCloudClient implements FirstSignInCloudClient {
  final operations = <Map<String, Object?>>[];
  LocalSyncAsset? uploadedAsset;
  bool _completed = false;

  @override
  Future<CloudSyncChangePage> listChanges({String? cursor, int limit = 100}) =>
      throw UnimplementedError();

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    final asset = uploadedAsset;
    return CloudSyncBootstrap(
      inventory: SyncLibraryInventory(
        notebookIds: _completed ? _notebookIds.toList() : const [],
      ),
      baseCursor: _completed ? 'cursor-complete' : 'cursor-empty',
      folders: const [],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: _completed && asset != null
          ? [
              CloudSyncAsset(
                id: asset.id,
                notebookId: asset.notebookId,
                kind: asset.kind,
                originalFilename: asset.filename,
                relativePath: asset.relativePath,
                contentType: asset.contentType,
                byteSize: asset.byteSize,
                sha256: asset.sha256,
                createdAt: DateTime.utc(2026, 8, 6),
                updatedAt: DateTime.utc(2026, 8, 6),
              ),
            ]
          : const [],
    );
  }

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    this.operations.addAll(operations);
    _notebookIds.addAll(
      operations
          .where((item) => item['resourceType'] == 'notebook')
          .map((item) => item['resourceId']! as String),
    );
    return const SyncMergeCommitResult(nextCursor: 'cursor-merged');
  }

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) => throw UnimplementedError();

  final Set<String> _notebookIds = {};

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) async {
    uploadedAsset = asset;
    return CloudAssetUploadSession(
      uploadId: 'upload-1',
      assetId: asset.id,
      uploadUrl: Uri.parse('https://objects.example.com/upload'),
      requiredHeaders: const {'Content-Type': 'image/png'},
    );
  }

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) async {
    expect(await asset.file.readAsBytes(), const [1, 2, 3, 4]);
  }

  @override
  Future<void> completeAssetUpload(String uploadId) async {
    expect(uploadId, 'upload-1');
    _completed = true;
  }

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();
}
