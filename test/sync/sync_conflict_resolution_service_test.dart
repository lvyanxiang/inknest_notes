import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflict_resolution_service.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

void main() {
  test(
    'resolves remotely then consumes the resolved conflict change',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-resolve-conflict-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      await FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).markChangesPageApplied('cursor-1');
      final store = FileSyncConflictStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      await store.applyConflict(_conflict());
      final cloud = _ResolutionCloudClient();
      final service = ApiSyncConflictResolutionService(
        cloudClient: cloud,
        pullService: IncrementalSyncPullService(
          repository: repository,
          cloudClient: cloud,
          rootDirectory: root,
        ),
      );

      final result = await service.resolveConflict(
        userId: 'user-1',
        deviceId: 'device-1',
        conflictId: 'conflict-1',
        resolution: SyncConflictResolution.keepOriginal,
      );

      expect(cloud.requestedResolution, SyncConflictResolution.keepOriginal);
      expect(result.pullResult.status, IncrementalSyncPullStatus.applied);
      expect(result.pullResult.pendingConflicts, isEmpty);
      expect(await store.loadPending(), isEmpty);
    },
  );

  test('maps a stale original to a recoverable resolution failure', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-resolve-stale-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final cloud = _ResolutionCloudClient(stale: true);
    final service = ApiSyncConflictResolutionService(
      cloudClient: cloud,
      pullService: IncrementalSyncPullService(
        repository: repository,
        cloudClient: cloud,
        rootDirectory: root,
      ),
    );

    await expectLater(
      service.resolveConflict(
        userId: 'user-1',
        deviceId: 'device-1',
        conflictId: 'conflict-1',
        resolution: SyncConflictResolution.useConflict,
      ),
      throwsA(
        isA<SyncConflictResolutionException>().having(
          (error) => error.failure,
          'failure',
          SyncConflictResolutionFailure.staleOriginal,
        ),
      ),
    );
  });
}

CloudSyncConflict _conflict({bool resolved = false}) => CloudSyncConflict(
  id: 'conflict-1',
  resourceType: 'page',
  originalResourceId: 'page-1',
  copyResourceId: 'page-copy-1',
  copyDisplayName: '第 1 页（冲突副本）',
  baseRevision: 0,
  currentRevision: 1,
  submittedContentHash: 'a' * 64,
  submittedContent: const {'strokes': <Object?>[]},
  currentContentHash: 'b' * 64,
  currentContent: const {'strokes': <Object?>[]},
  sourceDeviceId: 'device-2',
  status: resolved ? 'resolved' : 'pending',
  resolution: resolved ? 'keep_original' : null,
  resolvedByDeviceId: resolved ? 'device-1' : null,
  resolvedAt: resolved ? DateTime.utc(2026, 8, 7, 1) : null,
  createdAt: DateTime.utc(2026, 8, 7),
);

class _ResolutionCloudClient
    implements FirstSignInCloudClient, SyncConflictCloudClient {
  _ResolutionCloudClient({this.stale = false});

  final bool stale;
  SyncConflictResolution? requestedResolution;

  @override
  Future<CloudSyncConflict> resolveSyncConflict({
    required String conflictId,
    required SyncConflictResolution resolution,
  }) async {
    requestedResolution = resolution;
    if (stale) {
      throw const InkNestApiException(
        statusCode: 409,
        code: 'sync_conflict_resolution_stale',
        message: 'Stale.',
        details: {},
      );
    }
    return _conflict(resolved: true);
  }

  @override
  Future<CloudSyncChangePage> listChanges({
    String? cursor,
    int limit = 100,
  }) async {
    final resolved = _conflict(resolved: true);
    return CloudSyncChangePage(
      changes: [
        CloudSyncChange(
          changeId: 'change-conflict-resolved',
          resourceType: CloudSyncChangeResourceType.conflict,
          resourceId: resolved.id,
          operation: CloudSyncChangeOperation.upsert,
          revision: null,
          contentHash: null,
          payload: resolved.toJson(),
          deviceId: 'device-1',
          createdAt: DateTime.utc(2026, 8, 7, 1),
        ),
      ],
      nextCursor: 'cursor-2',
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncBootstrap> bootstrap() => throw UnimplementedError();

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) => throw UnimplementedError();

  @override
  Future<SyncContentCommitResult> commitSharedContent({
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

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();
}
