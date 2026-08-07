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
