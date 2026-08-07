import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_page_structure_service.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';

void main() {
  test('restores a deleted middle page at its original position', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-page-restore-structure-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    var notebook = await repository.createNotebook(title: 'Restored order');
    notebook = await repository.addPage(notebook);
    final localFirst = notebook.pageIds[0];
    final localThird = notebook.pageIds[1];
    final now = DateTime.utc(2026, 8, 7);
    final mappings = [
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 1,
        contentHash: 'd' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, localFirst),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 1,
        contentHash: 'a' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, localThird),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-3',
        revision: 2,
        contentHash: 'c' * 64,
      ),
    ];
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    await resourceMap.replaceAll(mappings);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: [notebook.id]),
      baseCursor: 'cursor-2',
      folders: const [],
      notebooks: const [],
      pages: [
        _page('remote-page-1', notebook.id, 0, 1, 'a' * 64, now),
        _page('remote-page-2', notebook.id, 1, 3, 'b' * 64, now),
        _page('remote-page-3', notebook.id, 2, 3, 'c' * 64, now),
      ],
      infiniteCanvases: const [],
      assets: const [],
    );
    final changes = [
      _change('remote-page-2', 3, 'b' * 64, now),
      _change('remote-page-3', 3, 'c' * 64, now),
    ];
    final tombstone = CloudSyncTombstone.fromJson({
      'id': 'tombstone-page-2',
      'resourceType': 'page',
      'resourceId': 'remote-page-2',
      'baseRevision': 1,
      'resourceRevision': 1,
      'deletedRevision': 2,
      'contentHash': 'b' * 64,
      'content': const {'strokes': <Object?>[]},
      'structureMetadata': {'notebookId': notebook.id, 'position': 1},
      'state': 'restored',
      'resolution': 'restored_snapshot',
      'restoredAt': now.toIso8601String(),
      'deletedAt': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });

    final result = await SyncPageStructureService(repository: repository)
        .applyRestorationIfSafe(
          changes: changes,
          bootstrap: bootstrap,
          mappings: mappings,
          resourceMap: resourceMap,
          changedTombstones: [tombstone],
        );

    expect(result?.restoredPageCount, 1);
    expect((await repository.listNotebooks()).single.pageIds, [
      localFirst,
      'remote-page-2',
      localThird,
    ]);
  });
}

CloudSyncPage _page(
  String id,
  String notebookId,
  int position,
  int revision,
  String hash,
  DateTime now,
) => CloudSyncPage(
  id: id,
  notebookId: notebookId,
  position: position,
  width: 768,
  height: 1024,
  coordinateSpaceVersion: 1,
  rotationQuarterTurns: 0,
  template: 'blank',
  revision: revision,
  contentHash: hash,
  content: const {'strokes': <Object?>[]},
  conflictOf: null,
  createdAt: now,
  updatedAt: now,
);

CloudSyncChange _change(String id, int revision, String hash, DateTime now) =>
    CloudSyncChange(
      changeId: 'change-$id',
      resourceType: CloudSyncChangeResourceType.page,
      resourceId: id,
      operation: CloudSyncChangeOperation.upsert,
      revision: revision,
      contentHash: hash,
      payload: const {},
      deviceId: 'device-2',
      createdAt: now,
    );
