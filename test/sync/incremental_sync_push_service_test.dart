import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';
import 'package:inknest_notes/sync/sync_structural_conflicts.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';

void main() {
  test('parses a deleted commit outcome from the server contract', () {
    final result = SyncContentCommitOperationResult.fromJson({
      'operationId': 'delete-1',
      'resourceType': 'notebook',
      'resourceId': 'notebook-1',
      'revision': 2,
      'contentHash': 'a' * 64,
      'outcome': 'deleted',
    });

    expect(result.outcome, 'deleted');
  });

  test('uploads pending operations and persists returned revision', () async {
    final fixture = await _PushFixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.service.push(
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(result.uploadedOperationCount, 1);
    expect(result.preservedConflictCount, 0);
    expect(fixture.cloud.requests.single.baseCursor, 'cursor-1');
    final state = await fixture.stateStore.loadSnapshot();
    expect(state.pendingOperations, isEmpty);
    expect(state.inFlightBatch, isNull);
    expect(state.lastAppliedCursor, 'cursor-1');
    final mapping = await fixture.resourceMap.find('page:local:page-1');
    expect(mapping?.revision, 2);
    expect(mapping?.contentHash, 'b' * 64);
  });

  test('response loss preserves the exact in-flight batch for retry', () async {
    final fixture = await _PushFixture.create(failuresRemaining: 1);
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.service.push(userId: 'user-1', deviceId: 'device-1'),
      throwsA(
        isA<IncrementalSyncPushException>().having(
          (error) => error.pendingOperationCount,
          'pendingOperationCount',
          1,
        ),
      ),
    );
    final failedState = await fixture.stateStore.loadSnapshot();
    expect(failedState.inFlightBatch, isNotNull);

    final result = await fixture.service.push(
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(result.uploadedOperationCount, 1);
    expect(fixture.cloud.requests, hasLength(2));
    expect(
      fixture.cloud.requests[1].idempotencyKey,
      fixture.cloud.requests[0].idempotencyKey,
    );
    expect(
      fixture.cloud.requests[1].operationId,
      fixture.cloud.requests[0].operationId,
    );
  });

  test(
    'uploads a notebook delete without advancing its mapped revision',
    () async {
      final fixture = await _PushFixture.create(delete: true);
      addTearDown(fixture.dispose);

      final result = await fixture.service.push(
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(result.uploadedOperationCount, 1);
      expect(fixture.cloud.requests.single.operation['operation'], 'delete');
      expect(
        fixture.cloud.requests.single.operation,
        isNot(contains('content')),
      );
      expect(
        (await fixture.resourceMap.find('notebook:notebook-1'))?.revision,
        1,
      );
    },
  );

  test(
    'reports delete/edit preservation separately from other conflicts',
    () async {
      final fixture = await _PushFixture.create(
        delete: true,
        outcome: 'delete_conflict',
      );
      addTearDown(fixture.dispose);

      final result = await fixture.service.push(
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(result.preservedConflictCount, 1);
      expect(result.preservedDeleteEditCount, 1);
    },
  );

  test('metadata commit waits for pull before advancing its mapping', () async {
    final fixture = await _PushFixture.create(metadata: true);
    addTearDown(fixture.dispose);

    await fixture.service.push(userId: 'user-1', deviceId: 'device-1');

    expect(fixture.cloud.requests.single.operation, isNot(contains('content')));
    expect(fixture.cloud.requests.single.operation['metadata'], {
      'title': 'After',
      'isArchived': true,
      'folderId': null,
    });
    final mapping = await fixture.resourceMap.find('notebook:notebook-1');
    expect(mapping?.revision, 1);
    expect(mapping?.notebookMetadata?['title'], 'Before');
  });

  test(
    'page content conflict retries its metadata without page content',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-page-conflict-',
      );
      addTearDown(() => root.delete(recursive: true));
      final stateStore = FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
        idFactory: (prefix) => '$prefix-1',
      );
      await stateStore.markChangesPageApplied('cursor-1');
      await stateStore.enqueuePage(
        resourceId: 'page-1',
        baseRevision: 1,
        content: const {'strokes': <Object?>[]},
        baseMetadata: const {
          'width': 768.0,
          'height': 1024.0,
          'coordinateSpaceVersion': 1,
          'rotationQuarterTurns': 0,
          'template': 'blank',
        },
        metadata: const {
          'width': 768.0,
          'height': 1024.0,
          'coordinateSpaceVersion': 1,
          'rotationQuarterTurns': 1,
          'template': 'grid',
        },
      );
      final cloud = _PushCloudClient(failuresRemaining: 0, outcome: 'conflict');

      final result = await IncrementalSyncPushService(
        cloudClient: cloud,
        repository: FileNotebookRepository(rootDirectory: root),
        rootDirectory: root,
      ).push(userId: 'user-1', deviceId: 'device-1');

      expect(result.preservedConflictCount, 1);
      expect(cloud.requests, hasLength(2));
      expect(cloud.requests.first.operation, contains('content'));
      expect(cloud.requests[1].operation['resourceType'], 'page');
      expect(cloud.requests[1].operation, isNot(contains('content')));
      expect(cloud.requests[1].operation['baseRevision'], 2);
      expect(
        cloud.requests[1].operation['metadata'],
        containsPair('template', 'grid'),
      );
    },
  );

  test('persists a metadata conflict for user-directed recovery', () async {
    final fixture = await _PushFixture.create(
      metadata: true,
      structuralConflict: true,
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.service.push(userId: 'user-1', deviceId: 'device-1'),
      throwsA(
        isA<IncrementalSyncPushException>().having(
          (error) => error.structuralConflicts.single.fields,
          'fields',
          ['title'],
        ),
      ),
    );

    final conflicts = await FileSyncStructuralConflictStore(
      rootDirectory: fixture.root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).load();
    expect(conflicts.single.localMetadata['title'], 'After');
    expect(conflicts.single.cloudMetadata['title'], 'Cloud');
    expect(conflicts.single.cloudRevision, 3);
  });

  test('retries a new attachment before committing its queued page', () async {
    final root = await Directory.systemTemp.createTemp('inknest-asset-push-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(title: 'With image');
    final source = File('${root.path}/source.png');
    await source.writeAsBytes([1, 2, 3, 4], flush: true);
    final image = await repository.importImage(
      notebook,
      source,
      position: Offset.zero,
      width: 100,
      height: 100,
    );
    final page = await repository.loadPage(notebook, notebook.pageIds.single);
    await repository.savePage(notebook, page.copyWith(images: [image]));
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
      idFactory: (prefix) => '$prefix-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    await stateStore.enqueueUpsert(
      resourceType: SyncResourceType.page,
      resourceId: 'remote-page-1',
      baseRevision: 1,
      content: page.copyWith(images: [image]).toJson(),
    );
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await resourceMap.replaceAll([
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 1,
        contentHash: 'a' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, notebook.pageIds.single),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 1,
        contentHash: 'a' * 64,
      ),
    ]);
    final cloud = _PushCloudClient(
      failuresRemaining: 0,
      assetFailuresRemaining: 1,
    );

    await expectLater(
      IncrementalSyncPushService(
        cloudClient: cloud,
        repository: repository,
        rootDirectory: root,
      ).push(userId: 'user-1', deviceId: 'device-1'),
      throwsA(
        isA<IncrementalSyncPushException>().having(
          (error) => error.pendingOperationCount,
          'pendingOperationCount',
          1,
        ),
      ),
    );
    expect((await stateStore.loadSnapshot()).pendingOperations, hasLength(1));
    expect(
      await resourceMap.hasCloudAsset(notebook.id, image.assetPath),
      isFalse,
    );

    await IncrementalSyncPushService(
      cloudClient: cloud,
      repository: repository,
      rootDirectory: root,
    ).push(userId: 'user-1', deviceId: 'device-1');

    expect(cloud.events, [
      'create-asset',
      'upload-asset',
      'create-asset',
      'upload-asset',
      'complete-asset',
      'bootstrap',
      'commit',
    ]);
    expect(
      await resourceMap.hasCloudAsset(notebook.id, image.assetPath),
      isTrue,
    );
  });
}

class _PushFixture {
  _PushFixture({
    required this.root,
    required this.stateStore,
    required this.resourceMap,
    required this.cloud,
    required this.repository,
  });

  final Directory root;
  final FileSyncStateStore stateStore;
  final FileSyncResourceMapStore resourceMap;
  final _PushCloudClient cloud;
  final FileNotebookRepository repository;

  IncrementalSyncPushService get service => IncrementalSyncPushService(
    cloudClient: cloud,
    repository: repository,
    rootDirectory: root,
  );

  static Future<_PushFixture> create({
    int failuresRemaining = 0,
    bool delete = false,
    bool metadata = false,
    bool structuralConflict = false,
    String? outcome,
  }) async {
    final root = await Directory.systemTemp.createTemp('inknest-push-');
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
      idFactory: (prefix) => '$prefix-1',
    );
    final repository = FileNotebookRepository(rootDirectory: root);
    await stateStore.markChangesPageApplied('cursor-1');
    if (delete) {
      await stateStore.enqueueDelete(
        resourceType: SyncResourceType.notebook,
        resourceId: 'notebook-1',
        baseRevision: 1,
      );
    } else if (metadata) {
      await stateStore.enqueueNotebookMetadata(
        resourceId: 'notebook-1',
        baseRevision: 1,
        baseMetadata: const {
          'title': 'Before',
          'isArchived': false,
          'folderId': null,
        },
        metadata: const {
          'title': 'After',
          'isArchived': true,
          'folderId': null,
        },
      );
    } else {
      await stateStore.enqueueUpsert(
        resourceType: SyncResourceType.page,
        resourceId: 'remote-page-1',
        baseRevision: 1,
        content: const {'strokes': <Object?>[]},
      );
    }
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await resourceMap.replaceAll([
      SyncResourceMapping(
        localKey: delete || metadata
            ? 'notebook:notebook-1'
            : 'page:local:page-1',
        resourceType: delete || metadata
            ? SyncResourceType.notebook
            : SyncResourceType.page,
        remoteResourceId: delete || metadata ? 'notebook-1' : 'remote-page-1',
        revision: 1,
        contentHash: 'a' * 64,
        notebookMetadata: metadata
            ? const {'title': 'Before', 'isArchived': false, 'folderId': null}
            : null,
      ),
    ]);
    return _PushFixture(
      root: root,
      stateStore: stateStore,
      resourceMap: resourceMap,
      cloud: _PushCloudClient(
        failuresRemaining: failuresRemaining,
        outcome: outcome,
        structuralConflict: structuralConflict,
      ),
      repository: repository,
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

class _PushRequest {
  const _PushRequest({
    required this.idempotencyKey,
    required this.baseCursor,
    required this.operationId,
    required this.operation,
  });

  final String idempotencyKey;
  final String baseCursor;
  final String operationId;
  final Map<String, Object?> operation;
}

class _PushCloudClient implements FirstSignInCloudClient {
  _PushCloudClient({
    required this.failuresRemaining,
    this.assetFailuresRemaining = 0,
    this.outcome,
    this.structuralConflict = false,
  });

  int failuresRemaining;
  int assetFailuresRemaining;
  final String? outcome;
  final bool structuralConflict;
  final List<_PushRequest> requests = [];
  final List<String> events = [];
  LocalSyncAsset? uploadedAsset;

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    events.add('commit');
    final operation = operations.single;
    requests.add(
      _PushRequest(
        idempotencyKey: idempotencyKey,
        baseCursor: baseCursor,
        operationId: operation['operationId']! as String,
        operation: operation,
      ),
    );
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('simulated response loss');
    }
    if (structuralConflict) {
      throw InkNestApiException(
        statusCode: 409,
        code: 'sync_notebook_metadata_conflict',
        message: 'conflict',
        details: {
          'operationId': operation['operationId'],
          'resourceType': 'notebook',
          'resourceId': 'notebook-1',
          'fields': const ['title'],
        },
      );
    }
    final requestedOutcome =
        outcome == 'conflict' && !operation.containsKey('content')
        ? 'applied'
        : outcome;
    return SyncContentCommitResult(
      idempotencyKey: idempotencyKey,
      nextCursor: 'cursor-2',
      results: [
        SyncContentCommitOperationResult(
          operationId: operation['operationId']! as String,
          resourceType: operation['resourceType']! as String,
          resourceId: operation['resourceId']! as String,
          revision: requests.length + 1,
          contentHash: 'b' * 64,
          outcome:
              requestedOutcome ??
              (operation['operation'] == 'delete' ? 'deleted' : 'applied'),
        ),
      ],
    );
  }

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    events.add('bootstrap');
    final asset = uploadedAsset;
    final now = DateTime.utc(2026, 8, 31);
    return CloudSyncBootstrap(
      inventory: SyncLibraryInventory(
        notebookIds: structuralConflict
            ? const ['notebook-1']
            : asset == null
            ? const []
            : [asset.notebookId],
      ),
      baseCursor: 'cursor-1',
      folders: const [],
      notebooks: structuralConflict
          ? [
              CloudSyncNotebook(
                id: 'notebook-1',
                folderId: null,
                title: 'Cloud',
                layoutMode: 'paged',
                isArchived: false,
                revision: 3,
                contentHash: 'c' * 64,
                content: const {},
                conflictOf: null,
                createdAt: now,
                updatedAt: now,
              ),
            ]
          : const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: asset == null
          ? const []
          : [
              CloudSyncAsset(
                id: asset.id,
                notebookId: asset.notebookId,
                kind: asset.kind,
                originalFilename: asset.filename,
                relativePath: asset.relativePath,
                contentType: asset.contentType,
                byteSize: asset.byteSize,
                sha256: asset.sha256,
                createdAt: DateTime.utc(2026, 8, 10),
                updatedAt: DateTime.utc(2026, 8, 10),
              ),
            ],
    );
  }

  @override
  Future<CloudSyncChangePage> listChanges({String? cursor, int limit = 100}) =>
      throw UnimplementedError();

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) => throw UnimplementedError();

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) async {
    events.add('create-asset');
    uploadedAsset = asset;
    return CloudAssetUploadSession(
      uploadId: 'upload-1',
      assetId: asset.id,
      uploadUrl: Uri.parse('https://objects.test/upload'),
      requiredHeaders: const {},
    );
  }

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) async {
    events.add('upload-asset');
    if (assetFailuresRemaining > 0) {
      assetFailuresRemaining--;
      throw StateError('simulated asset upload failure');
    }
  }

  @override
  Future<void> completeAssetUpload(String uploadId) async {
    events.add('complete-asset');
  }
}
