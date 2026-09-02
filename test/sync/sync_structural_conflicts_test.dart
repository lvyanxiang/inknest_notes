import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_structural_conflicts.dart';

void main() {
  test(
    'persists one structural conflict per resource across restart',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-structure-');
      addTearDown(() => root.delete(recursive: true));
      final store = FileSyncStructuralConflictStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      final conflict = SyncStructuralConflict(
        resourceType: SyncResourceType.page,
        resourceId: 'page-1',
        cloudRevision: 4,
        fields: const ['template'],
        localMetadata: const {'template': 'grid'},
        baseMetadata: const {'template': 'blank'},
        cloudMetadata: const {'template': 'ruled'},
      );

      await store.put(conflict);
      await store.put(conflict);

      final restored = await FileSyncStructuralConflictStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).load();
      expect(restored, hasLength(1));
      expect(restored.single.cloudMetadata, {'template': 'ruled'});
      await store.remove(conflict.id);
      expect(await store.load(), isEmpty);
    },
  );

  test('rebases local metadata and creates a fresh retry batch', () async {
    final root = await Directory.systemTemp.createTemp('inknest-rebase-');
    addTearDown(() => root.delete(recursive: true));
    var id = 0;
    final store = FileSyncStateStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
      idFactory: (prefix) => '$prefix-${id++}',
    );
    await store.markChangesPageApplied('cursor-1');
    await store.enqueueNotebookMetadata(
      resourceId: 'notebook-1',
      baseRevision: 2,
      baseMetadata: const {
        'title': 'Before',
        'isArchived': false,
        'folderId': null,
      },
      metadata: const {'title': 'Local', 'isArchived': false, 'folderId': null},
    );
    final failed = await store.prepareNextCommit();

    await store.requeueStructuralConflict(
      resourceKey: 'notebook:notebook-1',
      cloudRevision: 5,
      cloudMetadata: const {
        'title': 'Cloud',
        'isArchived': false,
        'folderId': null,
      },
      keepLocalMetadata: true,
    );

    final retry = await store.prepareNextCommit();
    expect(retry?.idempotencyKey, isNot(failed?.idempotencyKey));
    expect(retry?.operations.single.baseRevision, 5);
    expect(retry?.operations.single.baseMetadata?['title'], 'Cloud');
    expect(retry?.operations.single.metadata?['title'], 'Local');
  });
}
