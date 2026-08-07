import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  test('persists folder revision and name baseline', () async {
    final root = await Directory.systemTemp.createTemp('inknest-folder-map-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final folder = await repository.createFolder('Projects');
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(folderIds: [folder.id]),
      baseCursor: 'cursor-1',
      folders: [
        CloudSyncFolder(
          id: folder.id,
          name: folder.name,
          revision: 2,
          contentHash: 'f' * 64,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: const [],
    );
    final store = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    await store.replaceAll(
      await buildSyncResourceMappings(
        repository: repository,
        bootstrap: bootstrap,
      ),
    );

    final mapping = await store.find(folderSyncLocalKey(folder.id));
    expect(mapping?.resourceType, SyncResourceType.folder);
    expect(mapping?.revision, 2);
    expect(mapping?.folderMetadata, {'name': 'Projects'});
  });

  test('builds and persists local-to-cloud page mappings', () async {
    final root = await Directory.systemTemp.createTemp('inknest-map-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(title: 'Mapped notes');
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: [notebook.id]),
      baseCursor: 'cursor-1',
      folders: const [],
      notebooks: [
        CloudSyncNotebook(
          id: notebook.id,
          folderId: null,
          title: notebook.title,
          layoutMode: 'paged',
          isArchived: false,
          revision: 3,
          contentHash: 'a' * 64,
          content: const {},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      pages: [
        CloudSyncPage(
          id: 'remote-page-1',
          notebookId: notebook.id,
          position: 0,
          width: 768,
          height: 1024,
          coordinateSpaceVersion: 1,
          rotationQuarterTurns: 0,
          template: 'blank',
          revision: 4,
          contentHash: 'b' * 64,
          content: const {},
          conflictOf: null,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      infiniteCanvases: const [],
      assets: const [],
    );
    final store = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    await store.replaceAll(
      await buildSyncResourceMappings(
        repository: repository,
        bootstrap: bootstrap,
      ),
      cloudAssetKeys: [cloudAssetSyncKey(notebook.id, 'assets/image.png')],
    );

    final restartedStore = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    final page = await restartedStore.find(
      pageSyncLocalKey(notebook.id, notebook.pageIds.single),
    );
    expect(page?.resourceType, SyncResourceType.page);
    expect(page?.remoteResourceId, 'remote-page-1');
    expect(page?.revision, 4);
    final notebookMapping = await restartedStore.find(
      notebookSyncLocalKey(notebook.id),
    );
    expect(notebookMapping?.notebookMetadata, {
      'title': 'Mapped notes',
      'isArchived': false,
      'folderId': null,
      'pageOrder': ['remote-page-1'],
    });
    expect(
      await restartedStore.hasCloudAsset(notebook.id, 'assets/image.png'),
      isTrue,
    );

    await restartedStore.updateRemote(
      resourceType: SyncResourceType.page,
      remoteResourceId: 'remote-page-1',
      revision: 5,
      contentHash: 'c' * 64,
    );
    expect((await restartedStore.find(page!.localKey))?.revision, 5);
    expect(
      await restartedStore.hasCloudAsset(notebook.id, 'assets/image.png'),
      isTrue,
    );
  });
}
