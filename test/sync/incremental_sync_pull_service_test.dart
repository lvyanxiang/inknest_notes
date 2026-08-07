import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';
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

  test('rolls additive download back when final handoff fails', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-rollback-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    await Directory(
      '${root.path}/sync/user-1/device-1/resources.json',
    ).create(recursive: true);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: _cloudNotebookBootstrap(),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change('notebook', 'cloud-notebook'),
            _change('page', 'cloud-page'),
          ],
          nextCursor: 'cursor-2',
          hasMore: false,
        ),
      ],
    );

    await expectLater(
      IncrementalSyncPullService(
        repository: repository,
        cloudClient: cloud,
        rootDirectory: root,
      ).pull(userId: 'user-1', deviceId: 'device-1'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await repository.listNotebooks(), isEmpty);
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-1');
    expect(
      await Directory(
        '${root.path}/sync/user-1/device-1/resources.json',
      ).exists(),
      isTrue,
    );
  });

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

  test('applies a continuous notebook metadata update', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-metadata-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final folder = await repository.createFolder('Projects');
    final local = await repository.createNotebook(title: 'Before');
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
        notebookMetadata: const {
          'title': 'Before',
          'isArchived': false,
          'folderId': null,
        },
      ),
    ]);
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(
        folderIds: [folder.id],
        notebookIds: [local.id],
      ),
      baseCursor: 'bootstrap-cursor',
      folders: [
        CloudSyncFolder(
          id: folder.id,
          name: folder.name,
          revision: 0,
          contentHash: '',
          createdAt: folder.createdAt,
          updatedAt: folder.updatedAt,
        ),
      ],
      notebooks: [
        CloudSyncNotebook(
          id: local.id,
          folderId: folder.id,
          title: 'After',
          layoutMode: 'paged',
          isArchived: true,
          revision: 2,
          contentHash: 'a' * 64,
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
    final cloud = _PullCloudClient(
      bootstrapSnapshot: bootstrap,
      pages: [
        CloudSyncChangePage(
          changes: [
            _change('notebook', local.id, revision: 2, contentHash: 'a' * 64),
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
    final updated = (await repository.listNotebooks(archived: true)).single;
    expect(updated.title, 'After');
    expect(updated.folderId, folder.id);
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
  });

  test(
    'applies an atomic remote page reorder before advancing cursor',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-pull-order-');
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      var local = await repository.createNotebook(title: 'Ordered');
      local = await repository.addPage(local);
      final firstPageId = local.pageIds[0];
      final secondPageId = local.pageIds[1];
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
          notebookMetadata: {
            'title': 'Ordered',
            'isArchived': false,
            'folderId': null,
            'pageOrder': [firstPageId, secondPageId],
          },
        ),
        SyncResourceMapping(
          localKey: pageSyncLocalKey(local.id, firstPageId),
          resourceType: SyncResourceType.page,
          remoteResourceId: firstPageId,
          revision: 1,
          contentHash: 'b' * 64,
        ),
        SyncResourceMapping(
          localKey: pageSyncLocalKey(local.id, secondPageId),
          resourceType: SyncResourceType.page,
          remoteResourceId: secondPageId,
          revision: 1,
          contentHash: 'c' * 64,
        ),
      ]);
      final now = DateTime.utc(2026, 8, 7);
      final bootstrap = CloudSyncBootstrap(
        inventory: SyncLibraryInventory(notebookIds: [local.id]),
        baseCursor: 'bootstrap-cursor',
        folders: const [],
        notebooks: [
          CloudSyncNotebook(
            id: local.id,
            folderId: null,
            title: 'Ordered',
            layoutMode: 'paged',
            isArchived: false,
            revision: 2,
            contentHash: 'a' * 64,
            content: const {},
            conflictOf: null,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        pages: [
          CloudSyncPage(
            id: secondPageId,
            notebookId: local.id,
            position: 0,
            width: 768,
            height: 1024,
            coordinateSpaceVersion: 1,
            rotationQuarterTurns: 0,
            template: 'blank',
            revision: 2,
            contentHash: 'c' * 64,
            content: const {'strokes': <Object?>[]},
            conflictOf: null,
            createdAt: now,
            updatedAt: now,
          ),
          CloudSyncPage(
            id: firstPageId,
            notebookId: local.id,
            position: 1,
            width: 768,
            height: 1024,
            coordinateSpaceVersion: 1,
            rotationQuarterTurns: 0,
            template: 'blank',
            revision: 2,
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
      final cloud = _PullCloudClient(
        bootstrapSnapshot: bootstrap,
        pages: [
          CloudSyncChangePage(
            changes: [
              _change('page', firstPageId, revision: 2, contentHash: 'b' * 64),
              _change('page', secondPageId, revision: 2, contentHash: 'c' * 64),
              _change('notebook', local.id, revision: 2, contentHash: 'a' * 64),
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
      expect((await repository.listNotebooks()).single.pageIds, [
        secondPageId,
        firstPageId,
      ]);
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
    },
  );

  test('downloads a new cloud folder without a notebook', () async {
    final root = await Directory.systemTemp.createTemp('inknest-pull-folder-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(folderIds: const ['cloud-folder']),
      baseCursor: 'bootstrap-cursor',
      folders: [
        CloudSyncFolder(
          id: 'cloud-folder',
          name: 'Projects',
          revision: 1,
          contentHash: 'a' * 64,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: const [],
    );
    final cloud = _PullCloudClient(
      bootstrapSnapshot: bootstrap,
      pages: [
        CloudSyncChangePage(
          changes: [_change('folder', 'cloud-folder')],
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
    expect((await repository.listFolders()).single.name, 'Projects');
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
    expect(
      (await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).find(folderSyncLocalKey('cloud-folder')))?.revision,
      1,
    );
  });

  test('applies a continuous shared folder rename', () async {
    final root = await Directory.systemTemp.createTemp('inknest-pull-rename-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final folder = await repository.createFolder('Before');
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
        localKey: folderSyncLocalKey(folder.id),
        resourceType: SyncResourceType.folder,
        remoteResourceId: folder.id,
        revision: 1,
        contentHash: 'a' * 64,
        folderMetadata: const {'name': 'Before'},
      ),
    ]);
    final now = DateTime.utc(2026, 8, 7);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: CloudSyncBootstrap(
        inventory: SyncLibraryInventory(folderIds: [folder.id]),
        baseCursor: 'bootstrap-cursor',
        folders: [
          CloudSyncFolder(
            id: folder.id,
            name: 'After',
            revision: 2,
            contentHash: 'b' * 64,
            createdAt: folder.createdAt,
            updatedAt: now,
          ),
        ],
        notebooks: const [],
        pages: const [],
        infiniteCanvases: const [],
        assets: const [],
      ),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change('folder', folder.id, revision: 2, contentHash: 'b' * 64),
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
    expect((await repository.listFolders()).single.name, 'After');
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
  });

  test('deletes a shared folder and moves its notebook to root', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-folder-delete-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final folder = await repository.createFolder('Projects');
    final created = await repository.createNotebook(title: 'Plan');
    final notebook = await repository.moveNotebookToFolder(created, folder.id);
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
        localKey: folderSyncLocalKey(folder.id),
        resourceType: SyncResourceType.folder,
        remoteResourceId: folder.id,
        revision: 1,
        contentHash: 'f' * 64,
        folderMetadata: {'name': folder.name},
      ),
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 1,
        contentHash: 'e' * 64,
        notebookMetadata: {
          'title': notebook.title,
          'isArchived': false,
          'folderId': folder.id,
        },
      ),
    ]);
    final now = DateTime.utc(2026, 8, 7);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: CloudSyncBootstrap(
        inventory: SyncLibraryInventory(notebookIds: [notebook.id]),
        baseCursor: 'bootstrap-cursor',
        folders: const [],
        notebooks: [
          CloudSyncNotebook(
            id: notebook.id,
            folderId: null,
            title: notebook.title,
            layoutMode: 'paged',
            isArchived: false,
            revision: 2,
            contentHash: 'e' * 64,
            content: const {},
            conflictOf: null,
            createdAt: notebook.createdAt,
            updatedAt: now,
          ),
        ],
        pages: const [],
        infiniteCanvases: const [],
        assets: const [],
      ),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change(
              'notebook',
              notebook.id,
              revision: 2,
              contentHash: 'e' * 64,
            ),
            _change(
              'folder',
              folder.id,
              revision: 2,
              contentHash: 'f' * 64,
              operation: CloudSyncChangeOperation.delete,
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
    expect(result.deletedFolderCount, 1);
    expect(await repository.listFolders(), isEmpty);
    expect((await repository.listNotebooks()).single.id, notebook.id);
    expect((await repository.listNotebooks()).single.folderId, isNull);
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
  });

  test('confirms a locally created folder and publishes its mapping', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-own-folder-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final folder = await repository.createFolder('Projects');
    final stateStore = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await stateStore.markChangesPageApplied('cursor-1');
    final now = DateTime.utc(2026, 8, 7);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: CloudSyncBootstrap(
        inventory: SyncLibraryInventory(folderIds: [folder.id]),
        baseCursor: 'bootstrap-cursor',
        folders: [
          CloudSyncFolder(
            id: folder.id,
            name: folder.name,
            revision: 1,
            contentHash: 'a' * 64,
            createdAt: folder.createdAt,
            updatedAt: now,
          ),
        ],
        notebooks: const [],
        pages: const [],
        infiniteCanvases: const [],
        assets: const [],
      ),
      pages: [
        CloudSyncChangePage(
          changes: [_change('folder', folder.id, deviceId: 'device-1')],
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
    final mapping = await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).find(folderSyncLocalKey(folder.id));
    expect(mapping?.revision, 1);
    expect(mapping?.folderMetadata, {'name': 'Projects'});
  });

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

  test('applies a resolved conflict with its original-page update', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-resolved-conflict-',
    );
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
    final conflictStore = FileSyncConflictStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await conflictStore.applyChanges([_conflictChange()]);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: _sharedPageBootstrap(notebook.id),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change('page', 'remote-page', revision: 2, contentHash: 'e' * 64),
            _conflictChange(status: 'resolved', resolution: 'use_conflict'),
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
    expect(result.pendingConflicts, isEmpty);
    final page = await repository.loadPage(notebook, notebook.pageIds.single);
    expect(page.textBoxes.single.text, 'Cloud text');
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
  });

  test('appends a keep-both page copy before resolving the conflict', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-conflict-copy-',
    );
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
    final conflictStore = FileSyncConflictStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await conflictStore.applyChanges([_conflictChange()]);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: _keepBothPageBootstrap(notebook.id),
      pages: [
        CloudSyncChangePage(
          changes: [
            _change(
              'page',
              'page-conflict-copy',
              revision: 1,
              contentHash: 'f' * 64,
            ),
            _conflictChange(status: 'resolved', resolution: 'keep_both'),
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
    expect(result.pendingConflicts, isEmpty);
    final updated = (await repository.listNotebooks()).single;
    expect(updated.pageIds, [notebook.pageIds.single, 'page-conflict-copy']);
    final copy = await repository.loadPage(updated, 'page-conflict-copy');
    expect(copy.textBoxes.single.text, 'Offline copy');
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

  test(
    'removes a remotely deleted notebook after preserving recovery files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-pull-delete-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final notebook = await repository.createNotebook(
        title: 'Delete elsewhere',
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
      ]);
      final deletedAt = DateTime.utc(2026, 8, 7);
      final cloud = _PullCloudClient(
        bootstrapSnapshot: CloudSyncBootstrap(
          inventory: SyncLibraryInventory(),
          baseCursor: 'bootstrap-cursor',
          folders: const [],
          notebooks: const [],
          pages: const [],
          infiniteCanvases: const [],
          assets: const [],
        ),
        pages: [
          CloudSyncChangePage(
            changes: [
              CloudSyncChange(
                changeId: 'delete-notebook',
                resourceType: CloudSyncChangeResourceType.notebook,
                resourceId: notebook.id,
                operation: CloudSyncChangeOperation.delete,
                revision: 2,
                contentHash: 'a' * 64,
                payload: null,
                deviceId: 'device-2',
                createdAt: deletedAt,
              ),
              CloudSyncChange(
                changeId: 'tombstone-notebook',
                resourceType: CloudSyncChangeResourceType.tombstone,
                resourceId: 'tombstone-1',
                operation: CloudSyncChangeOperation.upsert,
                revision: null,
                contentHash: null,
                payload: {
                  'id': 'tombstone-1',
                  'resourceType': 'notebook',
                  'resourceId': notebook.id,
                  'baseRevision': 1,
                  'resourceRevision': 1,
                  'deletedRevision': 2,
                  'contentHash': 'a' * 64,
                  'content': const <String, Object?>{},
                  'state': 'active',
                  'deletedAt': deletedAt.toIso8601String(),
                  'createdAt': deletedAt.toIso8601String(),
                },
                deviceId: 'device-2',
                createdAt: deletedAt,
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
      expect(result.deletedNotebookCount, 1);
      expect(result.activeTombstones.single.id, 'tombstone-1');
      expect(await repository.listNotebooks(), isEmpty);
      final recovery = Directory(
        '${root.path}/sync/user-1/device-1/deleted/tombstone-1',
      );
      expect(await Directory('${recovery.path}/notebook').exists(), isTrue);
      expect(
        await File('${recovery.path}/local-notebook.json').exists(),
        isTrue,
      );
      expect(await File('${recovery.path}/tombstone.json').exists(), isTrue);
      expect(
        await File(
          '${root.path}/sync/user-1/device-1/tombstones.json',
        ).exists(),
        isTrue,
      );
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
    },
  );

  test(
    'restored Tombstone downloads its notebook and leaves Recently Deleted',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-pull-restore-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final stateStore = FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      await stateStore.markChangesPageApplied('cursor-1');
      final activePayload = _tombstonePayload();
      await FileSyncTombstoneStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).applyChanges([_tombstoneChange(activePayload)]);
      final restoredPayload = _tombstonePayload(restored: true);
      final cloud = _PullCloudClient(
        bootstrapSnapshot: _cloudNotebookBootstrap(),
        pages: [
          CloudSyncChangePage(
            changes: [
              _change('notebook', 'cloud-notebook', revision: 3),
              _change('page', 'cloud-page'),
              _tombstoneChange(restoredPayload),
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
      expect(result.activeTombstones, isEmpty);
      expect((await repository.listNotebooks()).single.title, 'Cloud notes');
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
    },
  );

  test('confirms a deletion originated by the same local device', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-pull-own-delete-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(title: 'Delete here');
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
    ]);
    await repository.deleteNotebook(notebook);
    final deletedAt = DateTime.utc(2026, 8, 7);
    final cloud = _PullCloudClient(
      bootstrapSnapshot: CloudSyncBootstrap(
        inventory: SyncLibraryInventory(),
        baseCursor: 'bootstrap-cursor',
        folders: const [],
        notebooks: const [],
        pages: const [],
        infiniteCanvases: const [],
        assets: const [],
      ),
      pages: [
        CloudSyncChangePage(
          changes: [
            CloudSyncChange(
              changeId: 'delete-notebook',
              resourceType: CloudSyncChangeResourceType.notebook,
              resourceId: notebook.id,
              operation: CloudSyncChangeOperation.delete,
              revision: 2,
              contentHash: 'a' * 64,
              payload: null,
              deviceId: 'device-1',
              createdAt: deletedAt,
            ),
            CloudSyncChange(
              changeId: 'tombstone-notebook',
              resourceType: CloudSyncChangeResourceType.tombstone,
              resourceId: 'tombstone-1',
              operation: CloudSyncChangeOperation.upsert,
              revision: null,
              contentHash: null,
              payload: {
                'id': 'tombstone-1',
                'resourceType': 'notebook',
                'resourceId': notebook.id,
                'baseRevision': 1,
                'resourceRevision': 1,
                'deletedRevision': 2,
                'contentHash': 'a' * 64,
                'content': const <String, Object?>{},
                'state': 'active',
                'deletedAt': deletedAt.toIso8601String(),
                'createdAt': deletedAt.toIso8601String(),
              },
              deviceId: 'device-1',
              createdAt: deletedAt,
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
    expect(result.deletedNotebookCount, 0);
    expect(result.confirmedLocalDeletionCount, 1);
    expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
    expect(
      await Directory('${root.path}/sync/user-1/device-1/deleted').exists(),
      isFalse,
    );
  });

  test(
    'persists a conflict-only change page before advancing Cursor',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-pull-conflict-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final stateStore = FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      await stateStore.markChangesPageApplied('cursor-1');
      final conflictPayload = {
        'id': 'conflict-1',
        'resourceType': 'page',
        'conflictOf': 'page-1',
        'copyResourceId': 'page-copy-1',
        'copyDisplayName': '第 1 页（冲突副本）',
        'baseRevision': 1,
        'currentRevision': 2,
        'submittedContentHash': 'a' * 64,
        'submittedContent': const {'strokes': <Object?>[]},
        'currentContentHash': 'b' * 64,
        'currentContent': const {'strokes': <Object?>[]},
        'sourceDeviceId': 'device-2',
        'status': 'pending',
        'createdAt': '2026-08-07T00:00:00Z',
      };
      final cloud = _PullCloudClient(
        bootstrapSnapshot: CloudSyncBootstrap(
          inventory: SyncLibraryInventory(),
          baseCursor: 'unused-bootstrap',
          folders: const [],
          notebooks: const [],
          pages: const [],
          infiniteCanvases: const [],
          assets: const [],
        ),
        pages: [
          CloudSyncChangePage(
            changes: [
              CloudSyncChange(
                changeId: 'change-conflict-1',
                resourceType: CloudSyncChangeResourceType.conflict,
                resourceId: 'conflict-1',
                operation: CloudSyncChangeOperation.upsert,
                revision: null,
                contentHash: null,
                payload: conflictPayload,
                deviceId: 'device-2',
                createdAt: DateTime.utc(2026, 8, 7),
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
      expect(result.receivedConflictCount, 1);
      expect(result.pendingConflicts.single.id, 'conflict-1');
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, 'cursor-2');
      expect(
        await File('${root.path}/sync/user-1/device-1/conflicts.json').exists(),
        isTrue,
      );

      final reloaded = await IncrementalSyncPullService(
        repository: repository,
        cloudClient: _PullCloudClient(
          bootstrapSnapshot: cloud.bootstrapSnapshot,
          pages: [
            CloudSyncChangePage(
              changes: [],
              nextCursor: 'cursor-2',
              hasMore: false,
            ),
          ],
        ),
        rootDirectory: root,
      ).pull(userId: 'user-1', deviceId: 'device-1');

      expect(reloaded.status, IncrementalSyncPullStatus.upToDate);
      expect(reloaded.pendingConflicts.single.id, 'conflict-1');
    },
  );
}

CloudSyncChange _change(
  String resourceType,
  String resourceId, {
  int revision = 1,
  String? contentHash,
  String deviceId = 'device-2',
  CloudSyncChangeOperation operation = CloudSyncChangeOperation.upsert,
}) {
  return CloudSyncChange(
    changeId: 'change-$resourceId',
    resourceType: CloudSyncChangeResourceType.fromApiValue(resourceType),
    resourceId: resourceId,
    operation: operation,
    revision: revision,
    contentHash: contentHash ?? 'a' * 64,
    payload: const {},
    deviceId: deviceId,
    createdAt: DateTime.utc(2026, 8, 7),
  );
}

CloudSyncChange _conflictChange({
  String status = 'pending',
  String? resolution,
}) {
  final payload = <String, Object?>{
    'id': 'conflict-1',
    'resourceType': 'page',
    'conflictOf': 'remote-page',
    'copyResourceId': 'page-conflict-copy',
    'copyDisplayName': '第 1 页（冲突副本）',
    'baseRevision': 0,
    'currentRevision': 1,
    'submittedContentHash': 'f' * 64,
    'submittedContent': const {'strokes': <Object?>[]},
    'currentContentHash': 'd' * 64,
    'currentContent': const {'strokes': <Object?>[]},
    'sourceDeviceId': 'device-2',
    'status': status,
    'createdAt': '2026-08-07T00:00:00Z',
  };
  if (resolution != null) {
    payload['resolution'] = resolution;
    payload['resolvedByDeviceId'] = 'device-1';
    payload['resolvedAt'] = '2026-08-07T01:00:00Z';
  }
  return CloudSyncChange(
    changeId: 'change-conflict-$status',
    resourceType: CloudSyncChangeResourceType.conflict,
    resourceId: 'conflict-1',
    operation: CloudSyncChangeOperation.upsert,
    revision: null,
    contentHash: null,
    payload: payload,
    deviceId: 'device-2',
    createdAt: DateTime.utc(2026, 8, 7),
  );
}

Map<String, Object?> _tombstonePayload({bool restored = false}) => {
  'id': 'tombstone-1',
  'resourceType': 'notebook',
  'resourceId': 'cloud-notebook',
  'baseRevision': 1,
  'resourceRevision': 1,
  'deletedRevision': 2,
  'contentHash': 'a' * 64,
  'content': const {'bookmarkedPageIds': <Object?>[]},
  'deletedByDeviceId': 'device-2',
  'deletedAt': '2026-08-07T00:00:00Z',
  'state': restored ? 'restored' : 'active',
  if (restored) 'resolution': 'restored_snapshot',
  if (restored) 'restoredByDeviceId': 'device-1',
  if (restored) 'restoredAt': '2026-08-07T01:00:00Z',
  'createdAt': '2026-08-07T00:00:00Z',
};

CloudSyncChange _tombstoneChange(Map<String, Object?> payload) =>
    CloudSyncChange(
      changeId: 'change-tombstone-${payload['state']}',
      resourceType: CloudSyncChangeResourceType.tombstone,
      resourceId: 'tombstone-1',
      operation: CloudSyncChangeOperation.upsert,
      revision: null,
      contentHash: null,
      payload: payload,
      deviceId: 'device-2',
      createdAt: DateTime.utc(2026, 8, 7),
    );

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

CloudSyncBootstrap _keepBothPageBootstrap(String notebookId) {
  final base = _sharedBootstrap(notebookId);
  final original = base.pages.single;
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
      original,
      CloudSyncPage(
        id: 'page-conflict-copy',
        notebookId: notebookId,
        position: 1,
        width: 768,
        height: 1024,
        coordinateSpaceVersion: 1,
        rotationQuarterTurns: 0,
        template: 'blank',
        revision: 1,
        contentHash: 'f' * 64,
        content: const {
          'strokes': <Object?>[],
          'textBoxes': [
            {
              'id': 'text-copy',
              'x': 10,
              'y': 20,
              'text': 'Offline copy',
              'width': 200,
              'color': 0xFF000000,
              'fontSize': 24,
              'style': 'regular',
            },
          ],
        },
        conflictOf: 'remote-page',
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
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
