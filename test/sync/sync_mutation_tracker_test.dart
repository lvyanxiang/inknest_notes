import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
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
}

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
