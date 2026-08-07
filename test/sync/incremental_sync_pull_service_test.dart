import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

void main() {
  test(
    'downloads additive cloud notebook before advancing final cursor',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-pull-');
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final stateStore = FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      await stateStore.markChangesPageApplied('cursor-1');
      final cloud = _PullCloudClient(
        bootstrapSnapshot: _cloudNotebookBootstrap(),
        pages: [
          CloudSyncChangePage(
            changes: [_change('notebook', 'cloud-notebook')],
            nextCursor: 'cursor-mid',
            hasMore: true,
          ),
          CloudSyncChangePage(
            changes: [_change('page', 'cloud-page')],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );

      final result = await IncrementalSyncPullService(
        repository: repository,
        cloudClient: cloud,
        rootDirectory: root,
      ).pull(userId: 'user-1', deviceId: 'device-1');

      expect(result.status, IncrementalSyncPullStatus.applied);
      expect(result.changeCount, 2);
      expect(result.downloadedNotebookCount, 1);
      final notebooks = await repository.listNotebooks();
      expect(notebooks.single.id, 'cloud-notebook');
      expect(notebooks.single.pageIds, ['cloud-page']);
      expect(
        (await repository.loadPage(notebooks.single, 'cloud-page')).id,
        'cloud-page',
      );
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
      expect(cloud.requestedCursors, ['cursor-1', 'cursor-mid']);
    },
  );

  test(
    'leaves cursor and local content unchanged for shared resource update',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-pull-shared-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final local = await repository.createNotebook(
        title: 'Local notes',
        layoutMode: NotebookLayoutMode.paged,
      );
      final stateStore = FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      await stateStore.markChangesPageApplied('cursor-1');
      final cloud = _PullCloudClient(
        bootstrapSnapshot: _sharedBootstrap(local.id),
        pages: [
          CloudSyncChangePage(
            changes: [_change('notebook', local.id)],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );

      final result = await IncrementalSyncPullService(
        repository: repository,
        cloudClient: cloud,
        rootDirectory: root,
      ).pull(userId: 'user-1', deviceId: 'device-1');

      expect(result.status, IncrementalSyncPullStatus.requiresReconciliation);
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-1');
      expect((await repository.listNotebooks()).single.title, 'Local notes');
    },
  );
}

CloudSyncChange _change(String resourceType, String resourceId) {
  return CloudSyncChange(
    changeId: 'change-$resourceId',
    resourceType: CloudSyncChangeResourceType.fromApiValue(resourceType),
    resourceId: resourceId,
    operation: CloudSyncChangeOperation.upsert,
    revision: 1,
    contentHash: 'a' * 64,
    payload: const {},
    deviceId: 'device-2',
    createdAt: DateTime.utc(2026, 8, 7),
  );
}

CloudSyncBootstrap _cloudNotebookBootstrap() {
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

CloudSyncBootstrap _sharedBootstrap(String notebookId) {
  final now = DateTime.utc(2026, 8, 7);
  return CloudSyncBootstrap(
    inventory: SyncLibraryInventory(notebookIds: [notebookId]),
    baseCursor: 'bootstrap-cursor',
    folders: const [],
    notebooks: [
      CloudSyncNotebook(
        id: notebookId,
        folderId: null,
        title: 'Cloud edit',
        layoutMode: 'paged',
        isArchived: false,
        revision: 2,
        contentHash: 'c' * 64,
        content: const {},
        conflictOf: null,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    pages: const [],
    infiniteCanvases: const [],
    assets: const [],
  );
}

class _PullCloudClient implements FirstSignInCloudClient {
  _PullCloudClient({
    required this.bootstrapSnapshot,
    required List<CloudSyncChangePage> pages,
  }) : _pages = List.of(pages);

  final CloudSyncBootstrap bootstrapSnapshot;
  final List<CloudSyncChangePage> _pages;
  final List<String?> requestedCursors = [];

  @override
  Future<CloudSyncBootstrap> bootstrap() async => bootstrapSnapshot;

  @override
  Future<CloudSyncChangePage> listChanges({
    String? cursor,
    int limit = 100,
  }) async {
    requestedCursors.add(cursor);
    return _pages.removeAt(0);
  }

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
}
