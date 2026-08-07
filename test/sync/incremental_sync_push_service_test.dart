import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

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
}

class _PushFixture {
  _PushFixture({
    required this.root,
    required this.stateStore,
    required this.resourceMap,
    required this.cloud,
  });

  final Directory root;
  final FileSyncStateStore stateStore;
  final FileSyncResourceMapStore resourceMap;
  final _PushCloudClient cloud;

  IncrementalSyncPushService get service =>
      IncrementalSyncPushService(cloudClient: cloud, rootDirectory: root);

  static Future<_PushFixture> create({
    int failuresRemaining = 0,
    bool delete = false,
    bool metadata = false,
    String? outcome,
  }) async {
    final root = await Directory.systemTemp.createTemp('inknest-push-');
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
      idFactory: (prefix) => '$prefix-1',
    );
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
      ),
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
  _PushCloudClient({required this.failuresRemaining, this.outcome});

  int failuresRemaining;
  final String? outcome;
  final List<_PushRequest> requests = [];

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
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
    return SyncContentCommitResult(
      idempotencyKey: idempotencyKey,
      nextCursor: 'cursor-2',
      results: [
        SyncContentCommitOperationResult(
          operationId: operation['operationId']! as String,
          resourceType: operation['resourceType']! as String,
          resourceId: operation['resourceId']! as String,
          revision: 2,
          contentHash: 'b' * 64,
          outcome:
              outcome ??
              (operation['operation'] == 'delete' ? 'deleted' : 'applied'),
        ),
      ],
    );
  }

  @override
  Future<CloudSyncBootstrap> bootstrap() => throw UnimplementedError();

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
