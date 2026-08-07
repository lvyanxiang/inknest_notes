import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  test('successful page save persists a coalesced sync upsert', () async {
    final root = await Directory.systemTemp.createTemp('inknest-track-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final notebook = await setupRepository.createNotebook(title: 'Tracked');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, notebook.pageIds.single),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 7,
        contentHash: 'a' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onPagePersisted: tracker.pageSaved,
    );

    await repository.savePage(
      notebook,
      NotePage(id: notebook.pageIds.single, width: 768, height: 1024),
    );
    await repository.savePage(
      notebook,
      NotePage(id: notebook.pageIds.single, width: 768, height: 1024),
    );

    final state = await FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).loadSnapshot();
    expect(state.pendingOperations, hasLength(1));
    final operation = state.pendingOperations.single;
    expect(operation.resourceId, 'remote-page-1');
    expect(operation.baseRevision, 7);
    expect(operation.content, contains('strokes'));
    expect(operation.content, isNot(contains('id')));
    expect(operation.content, isNot(contains('width')));
  });

  test('bookmark save queues rewritten notebook content only', () async {
    final root = await Directory.systemTemp.createTemp('inknest-bookmark-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final notebook = await setupRepository.createNotebook(title: 'Tracked');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 3,
        contentHash: 'a' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, notebook.pageIds.single),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 4,
        contentHash: 'b' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onNotebookContentPersisted: tracker.notebookContentSaved,
    );

    final renamed = await repository.renameNotebook(notebook, 'Local title');
    final archived = await repository.setNotebookArchived(renamed, true);
    expect((await _state(root)).pendingOperations, isEmpty);
    await repository.setPageBookmarked(archived, archived.pageIds.single, true);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.resourceType, SyncResourceType.notebook);
    expect(operation.baseRevision, 3);
    expect(operation.content['bookmarkedPageIds'], ['remote-page-1']);
    expect(operation.content, isNot(contains('title')));
    expect(operation.content, isNot(contains('isArchived')));
  });

  test(
    'rename archive and move coalesce one notebook metadata upsert',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-metadata-');
      addTearDown(() => root.delete(recursive: true));
      final setupRepository = FileNotebookRepository(rootDirectory: root);
      final notebook = await setupRepository.createNotebook(title: 'Before');
      final folder = await setupRepository.createFolder('Projects');
      await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).replaceAll([
        SyncResourceMapping(
          localKey: notebookSyncLocalKey(notebook.id),
          resourceType: SyncResourceType.notebook,
          remoteResourceId: notebook.id,
          revision: 4,
          contentHash: 'a' * 64,
          notebookMetadata: const {
            'title': 'Before',
            'isArchived': false,
            'folderId': null,
          },
        ),
      ]);
      final tracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: _session,
      );
      final repository = FileNotebookRepository(
        rootDirectory: root,
        onNotebookMetadataPersisted: tracker.notebookMetadataSaved,
      );

      final renamed = await repository.renameNotebook(notebook, 'After');
      final archived = await repository.setNotebookArchived(renamed, true);
      await repository.moveNotebookToFolder(archived, folder.id);

      final operation = (await _state(root)).pendingOperations.single;
      expect(operation.baseRevision, 4);
      expect(operation.includesContent, isFalse);
      expect(operation.baseMetadata, {
        'title': 'Before',
        'isArchived': false,
        'folderId': null,
      });
      expect(operation.metadata, {
        'title': 'After',
        'isArchived': true,
        'folderId': folder.id,
      });
      expect(operation.toJson(), isNot(contains('content')));
    },
  );

  test('page reorder queues the complete remote page order', () async {
    final root = await Directory.systemTemp.createTemp('inknest-page-order-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    var notebook = await setupRepository.createNotebook(title: 'Ordered');
    notebook = await setupRepository.addPage(notebook);
    final firstPageId = notebook.pageIds[0];
    final secondPageId = notebook.pageIds[1];
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 5,
        contentHash: 'a' * 64,
        notebookMetadata: const {
          'title': 'Ordered',
          'isArchived': false,
          'folderId': null,
          'pageOrder': ['remote-page-1', 'remote-page-2'],
        },
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, firstPageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 2,
        contentHash: 'b' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, secondPageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-2',
        revision: 3,
        contentHash: 'c' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onNotebookMetadataPersisted: tracker.notebookMetadataSaved,
    );

    await repository.movePage(notebook, secondPageId, 0);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.resourceType, SyncResourceType.notebook);
    expect(operation.baseRevision, 5);
    expect(operation.baseMetadata?['pageOrder'], [
      'remote-page-1',
      'remote-page-2',
    ]);
    expect(operation.metadata?['pageOrder'], [
      'remote-page-2',
      'remote-page-1',
    ]);
  });

  test('folder creation and rename coalesce one metadata upsert', () async {
    final root = await Directory.systemTemp.createTemp('inknest-folder-track-');
    addTearDown(() => root.delete(recursive: true));
    await FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).markChangesPageApplied('cursor-1');
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onFolderPersisted: tracker.folderSaved,
    );

    final folder = await repository.createFolder('Draft');
    await repository.renameFolder(folder, 'Projects');

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.resourceType, SyncResourceType.folder);
    expect(operation.resourceId, folder.id);
    expect(operation.baseRevision, 0);
    expect(operation.baseMetadata, isNull);
    expect(operation.metadata, {'name': 'Projects'});
    expect(operation.toJson(), isNot(contains('content')));
  });

  test('mapped folder rename retains its applied name baseline', () async {
    final root = await Directory.systemTemp.createTemp('inknest-folder-map-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final folder = await setupRepository.createFolder('Before');
    await FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).markChangesPageApplied('cursor-1');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: folderSyncLocalKey(folder.id),
        resourceType: SyncResourceType.folder,
        remoteResourceId: folder.id,
        revision: 3,
        contentHash: 'a' * 64,
        folderMetadata: const {'name': 'Before'},
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onFolderPersisted: tracker.folderSaved,
    );

    await repository.renameFolder(folder, 'After');

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.baseRevision, 3);
    expect(operation.baseMetadata, {'name': 'Before'});
    expect(operation.metadata, {'name': 'After'});
  });

  test(
    'deleting an unsent folder creation cancels the cloud operation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-folder-delete-local-',
      );
      addTearDown(() => root.delete(recursive: true));
      await FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).markChangesPageApplied('cursor-1');
      final tracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: _session,
      );
      final repository = FileNotebookRepository(
        rootDirectory: root,
        onFolderPersisted: tracker.folderSaved,
        onFolderDeleted: tracker.folderDeleted,
      );

      final folder = await repository.createFolder('Temporary');
      await repository.deleteFolder(folder);

      expect((await _state(root)).pendingOperations, isEmpty);
    },
  );

  test('mapped folder deletion queues its applied revision', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-folder-delete-mapped-',
    );
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final folder = await setupRepository.createFolder('Projects');
    await FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).markChangesPageApplied('cursor-1');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: folderSyncLocalKey(folder.id),
        resourceType: SyncResourceType.folder,
        remoteResourceId: 'remote-folder',
        revision: 4,
        contentHash: 'f' * 64,
        folderMetadata: const {'name': 'Projects'},
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onFolderDeleted: tracker.folderDeleted,
    );

    await repository.deleteFolder(folder);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.operation, SyncOperationKind.delete);
    expect(operation.resourceType, SyncResourceType.folder);
    expect(operation.resourceId, 'remote-folder');
    expect(operation.baseRevision, 4);
  });

  test(
    'infinite canvas save queues content without structural background',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-canvas-');
      addTearDown(() => root.delete(recursive: true));
      final setupRepository = FileNotebookRepository(rootDirectory: root);
      final notebook = await setupRepository.createNotebook(
        title: 'Canvas',
        layoutMode: NotebookLayoutMode.infiniteCanvas,
      );
      await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).replaceAll([
        SyncResourceMapping(
          localKey: canvasSyncLocalKey(notebook.id),
          resourceType: SyncResourceType.infiniteCanvas,
          remoteResourceId: 'remote-canvas-1',
          revision: 6,
          contentHash: 'c' * 64,
        ),
      ]);
      final tracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: _session,
      );
      final repository = FileNotebookRepository(
        rootDirectory: root,
        onInfiniteCanvasPersisted: tracker.infiniteCanvasSaved,
      );

      await repository.saveInfiniteCanvas(
        notebook,
        const InfiniteCanvasDocument(
          background: InfiniteCanvasBackground.grid,
          viewportFocus: Offset(12, 34),
          viewportScale: 2,
        ),
      );

      final operation = (await _state(root)).pendingOperations.single;
      expect(operation.resourceType, SyncResourceType.infiniteCanvas);
      expect(operation.resourceId, 'remote-canvas-1');
      expect(operation.content, isNot(contains('background')));
      expect(operation.content['viewportScale'], 2);
    },
  );

  test(
    'canvas with an unuploaded image stays out of the commit queue',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-canvas-asset-',
      );
      addTearDown(() => root.delete(recursive: true));
      final setupRepository = FileNotebookRepository(rootDirectory: root);
      final notebook = await setupRepository.createNotebook(
        title: 'Canvas',
        layoutMode: NotebookLayoutMode.infiniteCanvas,
      );
      await FileSyncResourceMapStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).replaceAll([
        SyncResourceMapping(
          localKey: canvasSyncLocalKey(notebook.id),
          resourceType: SyncResourceType.infiniteCanvas,
          remoteResourceId: 'remote-canvas-1',
          revision: 1,
          contentHash: 'd' * 64,
        ),
      ]);
      final tracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: _session,
      );
      final repository = FileNotebookRepository(
        rootDirectory: root,
        onInfiniteCanvasPersisted: tracker.infiniteCanvasSaved,
      );

      await repository.saveInfiniteCanvas(
        notebook,
        const InfiniteCanvasDocument(
          images: [
            NoteImage(
              id: 'image-1',
              position: Offset.zero,
              width: 100,
              height: 100,
              assetPath: 'assets/images/local.png',
            ),
          ],
        ),
      );

      expect((await _state(root)).pendingOperations, isEmpty);
    },
  );

  test('deleting a mapped notebook queues its remote delete', () async {
    final root = await Directory.systemTemp.createTemp('inknest-delete-track-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final notebook = await setupRepository.createNotebook(title: 'Tracked');
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 5,
        contentHash: 'a' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onNotebookDeleted: tracker.notebookDeleted,
    );

    await repository.deleteNotebook(notebook);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.operation, SyncOperationKind.delete);
    expect(operation.resourceType, SyncResourceType.notebook);
    expect(operation.resourceId, notebook.id);
    expect(operation.baseRevision, 5);
    expect(operation.toJson(), isNot(contains('content')));
    expect(await repository.listNotebooks(), isEmpty);
  });

  test('deleting a mapped trailing page queues its remote delete', () async {
    final root = await Directory.systemTemp.createTemp('inknest-page-delete-');
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    var notebook = await setupRepository.createNotebook(title: 'Tracked');
    notebook = await setupRepository.addPage(notebook);
    final deletedPageId = notebook.pageIds.last;
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, deletedPageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-2',
        revision: 4,
        contentHash: 'a' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onPageDeleted: tracker.pageDeleted,
    );

    await repository.deletePage(notebook, deletedPageId);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.operation, SyncOperationKind.delete);
    expect(operation.resourceType, SyncResourceType.page);
    expect(operation.resourceId, 'remote-page-2');
    expect(operation.baseRevision, 4);
    expect(operation.toJson(), isNot(contains('content')));
  });

  test('deleting a mapped middle page queues its remote delete', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-middle-delete-',
    );
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    var notebook = await setupRepository.createNotebook(title: 'Three pages');
    notebook = await setupRepository.addPage(notebook);
    notebook = await setupRepository.addPage(notebook);
    final middlePageId = notebook.pageIds[1];
    await FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).replaceAll([
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, middlePageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-2',
        revision: 4,
        contentHash: 'a' * 64,
      ),
    ]);
    final tracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: _session,
    );
    final repository = FileNotebookRepository(
      rootDirectory: root,
      onPageDeleted: tracker.pageDeleted,
    );

    await repository.deletePage(notebook, middlePageId);

    final operation = (await _state(root)).pendingOperations.single;
    expect(operation.operation, SyncOperationKind.delete);
    expect(operation.resourceType, SyncResourceType.page);
    expect(operation.resourceId, 'remote-page-2');
    expect(operation.baseRevision, 4);
  });
}

Future<SyncStateSnapshot> _state(Directory root) => FileSyncStateStore(
  rootDirectory: root,
  userId: 'user-1',
  deviceId: 'device-1',
).loadSnapshot();

InkNestAuthSession _session() {
  final now = DateTime.utc(2026, 8, 7);
  return InkNestAuthSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'bearer',
    expiresIn: 900,
    user: InkNestCloudUser(
      id: 'user-1',
      email: 'writer@example.com',
      createdAt: now,
    ),
    device: InkNestCloudDevice(
      id: 'device-1',
      name: 'Test device',
      platform: 'test',
      createdAt: now,
      lastSeenAt: now,
      current: true,
    ),
  );
}
