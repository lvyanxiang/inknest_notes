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
      throwsStateError,
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

  static Future<_PushFixture> create({int failuresRemaining = 0}) async {
    final root = await Directory.systemTemp.createTemp('inknest-push-');
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
      content: const {'strokes': <Object?>[]},
    );
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await resourceMap.replaceAll([
      SyncResourceMapping(
        localKey: 'page:local:page-1',
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 1,
        contentHash: 'a' * 64,
      ),
    ]);
    return _PushFixture(
      root: root,
      stateStore: stateStore,
      resourceMap: resourceMap,
      cloud: _PushCloudClient(failuresRemaining: failuresRemaining),
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

class _PushRequest {
  const _PushRequest({
    required this.idempotencyKey,
    required this.baseCursor,
    required this.operationId,
  });

  final String idempotencyKey;
  final String baseCursor;
  final String operationId;
}

class _PushCloudClient implements FirstSignInCloudClient {
  _PushCloudClient({required this.failuresRemaining});

  int failuresRemaining;
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
          outcome: 'applied',
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
