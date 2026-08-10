import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_notebook_deletion_service.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  test('retries a recovered canvas-notebook deletion idempotently', () async {
    final root = await Directory.systemTemp.createTemp('inknest-delete-retry-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    final notebook = await repository.createNotebook(
      title: 'Retry canvas delete',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    final deletedAt = DateTime.utc(2026, 8, 7);
    final changes = [
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
    ];
    final mappings = [
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: notebook.id,
        revision: 1,
        contentHash: 'a' * 64,
      ),
    ];
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(),
      baseCursor: 'bootstrap-cursor',
      folders: const [],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: const [],
    );
    final service = SyncNotebookDeletionService(rootDirectory: root);

    final first = await service.applyIfSafe(
      changes: changes,
      bootstrap: bootstrap,
      mappings: mappings,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    final retry = await service.applyIfSafe(
      changes: changes,
      bootstrap: bootstrap,
      mappings: mappings,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(first?.deletedNotebookCount, 1);
    expect(retry?.deletedNotebookCount, 1);
    expect(await repository.listNotebooks(), isEmpty);
    expect(
      await Directory(
        '${root.path}/sync/user-1/device-1/deleted/tombstone-1/notebook',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${root.path}/sync/user-1/device-1/deleted/tombstone-1/'
        'notebook/canvas.json',
      ).exists(),
      isTrue,
    );
  });
}
