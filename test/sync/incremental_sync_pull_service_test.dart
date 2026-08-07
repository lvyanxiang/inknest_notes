import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
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
    'applies continuous shared notebook content before advancing cursor',
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
      await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).replaceAll([
        SyncResourceMapping(
          localKey: notebookSyncLocalKey(local.id),
          resourceType: SyncResourceType.notebook,
          remoteResourceId: local.id,
          revision: 1,
          contentHash: 'a' * 64,
        ),
        SyncResourceMapping(
          localKey: pageSyncLocalKey(local.id, local.pageIds.single),
          resourceType: SyncResourceType.page,
          remoteResourceId: 'remote-page',
          revision: 1,
          contentHash: 'd' * 64,
        ),
      ]);
      final cloud = _PullCloudClient(
        bootstrapSnapshot: _sharedBootstrap(local.id),
        pages: [
          CloudSyncChangePage(
            changes: [
              _change('notebook', local.id, revision: 2, contentHash: 'c' * 64),
            ],
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
      expect(result.appliedSharedResourceCount, 1);
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
      expect((await repository.listNotebooks()).single.bookmarkedPageIds, [
        local.pageIds.single,
      ]);
    },
  );

  test('applies a continuous shared page content update', () async {
    final root = await Directory.systemTemp.createTemp('inknest-pull-page-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(title: 'Local notes');
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
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
        remoteResourceId: 'remote-page',
        revision: 1,
        contentHash: 'd' * 64,
      ),
    ]);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: _sharedPageBootstrap(notebook.id),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change('page', 'remote-page', revision: 2, contentHash: 'e' * 64),
          ],
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
    final page = await repository.loadPage(notebook, notebook.pageIds.single);
    expect(page.textBoxes.single.text, 'Cloud text');
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
  });

  test('applies a continuous shared infinite-canvas update', () async {
    final root = await Directory.systemTemp.createTemp('inknest-pull-canvas-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(
      title: 'Canvas',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 1,
        contentHash: 'a' * 64,
      ),
      SyncResourceMapping(
        localKey: canvasSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.infiniteCanvas,
        remoteResourceId: 'remote-canvas',
        revision: 1,
        contentHash: 'f' * 64,
      ),
    ]);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: _sharedCanvasBootstrap(notebook.id),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change(
              'infinite_canvas',
              'remote-canvas',
              revision: 2,
              contentHash: '9' * 64,
            ),
          ],
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
    final canvas = await repository.loadInfiniteCanvas(notebook);
    expect(canvas.viewportScale, 2);
    expect(canvas.viewportFocus.dx, 9);
  });
}

CloudSyncChange _change(
  String resourceType,
  String resourceId, {
  int revision = 1,
  String? contentHash,
}) {
  return CloudSyncChange(
    changeId: 'change-$resourceId',
    resourceType: CloudSyncChangeResourceType.fromApiValue(resourceType),
    resourceId: resourceId,
    operation: CloudSyncChangeOperation.upsert,
    revision: revision,
    contentHash: contentHash ?? 'a' * 64,
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
        title: 'Local notes',
        layoutMode: 'paged',
        isArchived: false,
        revision: 2,
        contentHash: 'c' * 64,
        content: const {
          'bookmarkedPageIds': ['remote-page'],
        },
        conflictOf: null,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    pages: [
      CloudSyncPage(
        id: 'remote-page',
        notebookId: notebookId,
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

CloudSyncBootstrap _sharedPageBootstrap(String notebookId) {
  final base = _sharedBootstrap(notebookId);
  final page = base.pages.single;
  return CloudSyncBootstrap(
    inventory: base.inventory,
    baseCursor: base.baseCursor,
    folders: base.folders,
    notebooks: [
      CloudSyncNotebook(
        id: notebookId,
        folderId: null,
        title: 'Local notes',
        layoutMode: 'paged',
        isArchived: false,
        revision: 1,
        contentHash: 'a' * 64,
        content: const {},
        conflictOf: null,
        createdAt: base.notebooks.single.createdAt,
        updatedAt: base.notebooks.single.updatedAt,
      ),
    ],
    pages: [
      CloudSyncPage(
        id: page.id,
        notebookId: notebookId,
        position: 0,
        width: 768,
        height: 1024,
        coordinateSpaceVersion: 1,
        rotationQuarterTurns: 0,
        template: 'blank',
        revision: 2,
        contentHash: 'e' * 64,
        content: const {
          'strokes': <Object?>[],
          'textBoxes': [
            {
              'id': 'text-1',
              'x': 10,
              'y': 20,
              'text': 'Cloud text',
              'width': 200,
              'color': 0xFF000000,
              'fontSize': 24,
              'style': 'regular',
            },
          ],
        },
        conflictOf: null,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
      ),
    ],
    infiniteCanvases: const [],
    assets: const [],
  );
}

CloudSyncBootstrap _sharedCanvasBootstrap(String notebookId) {
  final now = DateTime.utc(2026, 8, 7);
  return CloudSyncBootstrap(
    inventory: SyncLibraryInventory(notebookIds: [notebookId]),
    baseCursor: 'bootstrap-cursor',
    folders: const [],
    notebooks: [
      CloudSyncNotebook(
        id: notebookId,
        folderId: null,
        title: 'Canvas',
        layoutMode: 'infiniteCanvas',
        isArchived: false,
        revision: 1,
        contentHash: 'a' * 64,
        content: const {},
        conflictOf: null,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    pages: const [],
    infiniteCanvases: [
      CloudSyncInfiniteCanvas(
        id: 'remote-canvas',
        notebookId: notebookId,
        background: 'blank',
        revision: 2,
        contentHash: '9' * 64,
        content: const {
          'strokes': <Object?>[],
          'textBoxes': <Object?>[],
          'images': <Object?>[],
          'shapes': <Object?>[],
          'viewportFocus': {'dx': 9, 'dy': 12},
          'viewportScale': 2,
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
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
