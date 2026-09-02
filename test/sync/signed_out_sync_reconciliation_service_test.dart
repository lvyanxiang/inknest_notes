import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/signed_out_sync_mutations.dart';
import 'package:inknest_notes/sync/signed_out_sync_reconciliation_service.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  test(
    'a signed-out page edit survives restart and rejoins the same account queue',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-signed-out-edit-',
      );
      addTearDown(() => root.delete(recursive: true));
      final setupRepository = FileNotebookRepository(rootDirectory: root);
      final notebook = await setupRepository.createNotebook(title: 'Mapped');
      final pageId = notebook.pageIds.single;
      await _initializeScope(
        root,
        userId: 'user-1',
        deviceId: 'device-1',
        mappings: [
          SyncResourceMapping(
            localKey: pageSyncLocalKey(notebook.id, pageId),
            resourceType: SyncResourceType.page,
            remoteResourceId: 'remote-page-1',
            revision: 7,
            contentHash: 'a' * 64,
          ),
        ],
      );
      final signedOutTracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: () => null,
      );
      final signedOutRepository = FileNotebookRepository(
        rootDirectory: root,
        onPagePersisted: signedOutTracker.pageSaved,
      );

      await signedOutRepository.savePage(
        notebook,
        NotePage(
          id: pageId,
          width: 768,
          height: 1024,
          strokes: [
            Stroke(
              id: 'offline-stroke',
              tool: ToolType.pen,
              color: Color(0xff000000),
              width: 3,
              points: [
                StrokePoint(
                  offset: Offset(10, 20),
                  pressure: 0.5,
                  time: DateTime.utc(2026, 8, 26),
                ),
              ],
            ),
          ],
        ),
      );
      expect(
        (await _state(root, 'user-1', 'device-1')).pendingOperations,
        isEmpty,
      );

      final restartedTracker = SyncMutationTracker(
        rootDirectory: root,
        activeSession: () => _session('user-1', 'device-1'),
      );
      final result = await SignedOutSyncReconciliationService(
        repository: FileNotebookRepository(rootDirectory: root),
        rootDirectory: root,
        mutationTracker: restartedTracker,
      ).reconcile(userId: 'user-1', deviceId: 'device-1');

      expect(result.queuedMutationCount, 1);
      final operation = (await _state(
        root,
        'user-1',
        'device-1',
      )).pendingOperations.single;
      expect(operation.resourceType, SyncResourceType.page);
      expect(operation.resourceId, 'remote-page-1');
      expect(operation.baseRevision, 7);
      expect(operation.content['strokes'], hasLength(1));
      expect(
        await FileSignedOutSyncMutationStore(
          rootDirectory: root,
        ).loadForScope(userId: 'user-1', deviceId: 'device-1'),
        isEmpty,
      );
    },
  );

  test('a different account cannot consume a prior signed-out edit', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-signed-out-scope-',
    );
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final notebook = await setupRepository.createNotebook(title: 'Mapped');
    final pageId = notebook.pageIds.single;
    final localKey = pageSyncLocalKey(notebook.id, pageId);
    await _initializeScope(
      root,
      userId: 'user-1',
      deviceId: 'device-1',
      mappings: [
        SyncResourceMapping(
          localKey: localKey,
          resourceType: SyncResourceType.page,
          remoteResourceId: 'user-1-page',
          revision: 2,
          contentHash: 'a' * 64,
        ),
      ],
    );
    final signedOutTracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: () => null,
    );
    await signedOutTracker.pageSaved(
      notebook,
      await setupRepository.loadPage(notebook, pageId),
    );

    await _initializeScope(
      root,
      userId: 'user-2',
      deviceId: 'device-2',
      mappings: [
        SyncResourceMapping(
          localKey: localKey,
          resourceType: SyncResourceType.page,
          remoteResourceId: 'user-2-page',
          revision: 4,
          contentHash: 'b' * 64,
        ),
      ],
    );
    final otherAccountResult = await SignedOutSyncReconciliationService(
      repository: setupRepository,
      rootDirectory: root,
      mutationTracker: SyncMutationTracker(
        rootDirectory: root,
        activeSession: () => _session('user-2', 'device-2'),
      ),
    ).reconcile(userId: 'user-2', deviceId: 'device-2');

    expect(otherAccountResult.queuedMutationCount, 0);
    expect(
      (await _state(root, 'user-2', 'device-2')).pendingOperations,
      isEmpty,
    );
    expect(
      await FileSignedOutSyncMutationStore(
        rootDirectory: root,
      ).loadForScope(userId: 'user-1', deviceId: 'device-1'),
      hasLength(1),
    );
  });

  test('folder notebook and canvas edits rejoin their mapped queues', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-signed-out-metadata-',
    );
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final folder = await setupRepository.createFolder('Before folder');
    final notebook = await setupRepository.createNotebook(
      title: 'Before notebook',
    );
    final canvasNotebook = await setupRepository.createNotebook(
      title: 'Canvas',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    await _initializeScope(
      root,
      userId: 'user-1',
      deviceId: 'device-1',
      mappings: [
        SyncResourceMapping(
          localKey: folderSyncLocalKey(folder.id),
          resourceType: SyncResourceType.folder,
          remoteResourceId: 'remote-folder-1',
          revision: 2,
          contentHash: 'a' * 64,
          folderMetadata: const {'name': 'Before folder'},
        ),
        SyncResourceMapping(
          localKey: notebookSyncLocalKey(notebook.id),
          resourceType: SyncResourceType.notebook,
          remoteResourceId: 'remote-notebook-1',
          revision: 3,
          contentHash: 'b' * 64,
          notebookMetadata: const {
            'title': 'Before notebook',
            'isArchived': false,
            'folderId': null,
            'pageOrder': ['remote-page-1'],
          },
        ),
        SyncResourceMapping(
          localKey: pageSyncLocalKey(notebook.id, notebook.pageIds.single),
          resourceType: SyncResourceType.page,
          remoteResourceId: 'remote-page-1',
          revision: 1,
          contentHash: 'c' * 64,
        ),
        SyncResourceMapping(
          localKey: canvasSyncLocalKey(canvasNotebook.id),
          resourceType: SyncResourceType.infiniteCanvas,
          remoteResourceId: 'remote-canvas-1',
          revision: 4,
          contentHash: 'd' * 64,
          infiniteCanvasMetadata: const {'background': 'blank'},
        ),
      ],
    );
    final signedOutTracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: () => null,
    );
    final signedOutRepository = FileNotebookRepository(
      rootDirectory: root,
      onFolderPersisted: signedOutTracker.folderSaved,
      onNotebookMetadataPersisted: signedOutTracker.notebookMetadataSaved,
      onInfiniteCanvasPersisted: signedOutTracker.infiniteCanvasSaved,
    );

    await signedOutRepository.renameFolder(folder, 'After folder');
    await signedOutRepository.renameNotebook(notebook, 'After notebook');
    await signedOutRepository.saveInfiniteCanvas(
      canvasNotebook,
      const InfiniteCanvasDocument(
        background: InfiniteCanvasBackground.grid,
        viewportScale: 2,
      ),
    );

    final result = await SignedOutSyncReconciliationService(
      repository: FileNotebookRepository(rootDirectory: root),
      rootDirectory: root,
      mutationTracker: SyncMutationTracker(
        rootDirectory: root,
        activeSession: () => _session('user-1', 'device-1'),
      ),
    ).reconcile(userId: 'user-1', deviceId: 'device-1');

    expect(result.queuedMutationCount, 3);
    final operations = (await _state(
      root,
      'user-1',
      'device-1',
    )).pendingOperations;
    expect(operations, hasLength(3));
    expect(
      operations
          .singleWhere(
            (operation) => operation.resourceType == SyncResourceType.folder,
          )
          .metadata,
      {'name': 'After folder'},
    );
    expect(
      operations
          .singleWhere(
            (operation) => operation.resourceType == SyncResourceType.notebook,
          )
          .metadata?['title'],
      'After notebook',
    );
    expect(
      operations
          .singleWhere(
            (operation) =>
                operation.resourceType == SyncResourceType.infiniteCanvas,
          )
          .metadata,
      {'background': 'grid'},
    );
  });

  test('an explicit signed-out notebook delete rejoins as a delete', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-signed-out-delete-',
    );
    addTearDown(() => root.delete(recursive: true));
    final setupRepository = FileNotebookRepository(rootDirectory: root);
    final notebook = await setupRepository.createNotebook(title: 'Delete me');
    await _initializeScope(
      root,
      userId: 'user-1',
      deviceId: 'device-1',
      mappings: [
        SyncResourceMapping(
          localKey: notebookSyncLocalKey(notebook.id),
          resourceType: SyncResourceType.notebook,
          remoteResourceId: 'remote-notebook-1',
          revision: 5,
          contentHash: 'c' * 64,
          notebookMetadata: const {
            'title': 'Delete me',
            'isArchived': false,
            'folderId': null,
            'pageOrder': ['remote-page-1'],
          },
        ),
      ],
    );
    final signedOutTracker = SyncMutationTracker(
      rootDirectory: root,
      activeSession: () => null,
    );
    await signedOutTracker.notebookMetadataSaved(notebook);
    await FileNotebookRepository(
      rootDirectory: root,
      onNotebookDeleted: signedOutTracker.notebookDeleted,
    ).deleteNotebook(notebook);
    expect(
      (await FileSignedOutSyncMutationStore(
        rootDirectory: root,
      ).loadForScope(userId: 'user-1', deviceId: 'device-1')).single.kind,
      SignedOutSyncMutationKind.delete,
    );

    final result = await SignedOutSyncReconciliationService(
      repository: FileNotebookRepository(rootDirectory: root),
      rootDirectory: root,
      mutationTracker: SyncMutationTracker(
        rootDirectory: root,
        activeSession: () => _session('user-1', 'device-1'),
      ),
    ).reconcile(userId: 'user-1', deviceId: 'device-1');

    expect(result.queuedMutationCount, 1);
    final operation = (await _state(
      root,
      'user-1',
      'device-1',
    )).pendingOperations.single;
    expect(operation.operation, SyncOperationKind.delete);
    expect(operation.resourceType, SyncResourceType.notebook);
    expect(operation.resourceId, 'remote-notebook-1');
    expect(operation.baseRevision, 5);
  });
}

Future<void> _initializeScope(
  Directory root, {
  required String userId,
  required String deviceId,
  required List<SyncResourceMapping> mappings,
}) async {
  await FileSyncResourceMapStore(
    rootDirectory: root,
    userId: userId,
    deviceId: deviceId,
  ).replaceAll(mappings);
  await FileSyncStateStore(
    rootDirectory: root,
    userId: userId,
    deviceId: deviceId,
  ).markChangesPageApplied('cursor-$userId-$deviceId');
}

Future<SyncStateSnapshot> _state(
  Directory root,
  String userId,
  String deviceId,
) => FileSyncStateStore(
  rootDirectory: root,
  userId: userId,
  deviceId: deviceId,
).loadSnapshot();

InkNestAuthSession _session(String userId, String deviceId) {
  final now = DateTime.utc(2026, 8, 26);
  return InkNestAuthSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'bearer',
    expiresIn: 900,
    user: InkNestCloudUser(
      id: userId,
      email: '$userId@example.com',
      createdAt: now,
    ),
    device: InkNestCloudDevice(
      id: deviceId,
      name: 'Test device',
      platform: 'test',
      createdAt: now,
      lastSeenAt: now,
      current: true,
    ),
  );
}
