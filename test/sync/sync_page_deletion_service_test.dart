import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_page_deletion_service.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  test('preserves and applies a remote trailing-page deletion', () async {
    final fixture = await _PageDeletionFixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.service.applyIfSafe(
      changes: fixture.changes(deviceId: 'device-2'),
      bootstrap: fixture.bootstrap,
      mappings: fixture.mappings,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(result?.deletedPageCount, 1);
    expect(result?.confirmedLocalPageDeletionCount, 0);
    final notebook = (await fixture.repository.listNotebooks()).single;
    expect(notebook.pageIds, [fixture.firstPageId]);
    final recovery = Directory(
      '${fixture.root.path}/sync/user-1/device-1/deleted/tombstone-page-2',
    );
    expect(await File('${recovery.path}/page.json').exists(), isTrue);
    expect(await File('${recovery.path}/location.json').exists(), isTrue);
    expect(await File('${recovery.path}/tombstone.json').exists(), isTrue);
  });

  test('confirms a trailing-page deletion from the same device', () async {
    final fixture = await _PageDeletionFixture.create();
    addTearDown(fixture.dispose);
    await fixture.repository.deletePage(fixture.notebook, fixture.lastPageId);

    final result = await fixture.service.applyIfSafe(
      changes: fixture.changes(deviceId: 'device-1'),
      bootstrap: fixture.bootstrap,
      mappings: fixture.mappings,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(result?.deletedPageCount, 0);
    expect(result?.confirmedLocalPageDeletionCount, 1);
  });

  test('applies a middle-page deletion and keeps the compacted order', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-middle-page-apply-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = FileNotebookRepository(rootDirectory: root);
    var notebook = await repository.createNotebook(title: 'Three pages');
    notebook = await repository.addPage(notebook);
    notebook = await repository.addPage(notebook);
    final localIds = notebook.pageIds.toList();
    final hashes = ['a' * 64, 'b' * 64, 'c' * 64];
    final mappings = [
      for (final (index, localId) in localIds.indexed)
        SyncResourceMapping(
          localKey: pageSyncLocalKey(notebook.id, localId),
          resourceType: SyncResourceType.page,
          remoteResourceId: 'remote-page-${index + 1}',
          revision: 1,
          contentHash: hashes[index],
        ),
    ];
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: [notebook.id]),
      baseCursor: 'bootstrap-cursor',
      folders: const [],
      notebooks: const [],
      pages: [
        _cloudPage(
          id: 'remote-page-1',
          notebookId: notebook.id,
          position: 0,
          revision: 1,
          hash: hashes[0],
          now: now,
        ),
        _cloudPage(
          id: 'remote-page-3',
          notebookId: notebook.id,
          position: 1,
          revision: 2,
          hash: hashes[2],
          now: now,
        ),
      ],
      infiniteCanvases: const [],
      assets: const [],
    );
    final changes = [
      CloudSyncChange(
        changeId: 'shift-page-3',
        resourceType: CloudSyncChangeResourceType.page,
        resourceId: 'remote-page-3',
        operation: CloudSyncChangeOperation.upsert,
        revision: 2,
        contentHash: hashes[2],
        payload: const {},
        deviceId: 'device-2',
        createdAt: now,
      ),
      CloudSyncChange(
        changeId: 'delete-page-2',
        resourceType: CloudSyncChangeResourceType.page,
        resourceId: 'remote-page-2',
        operation: CloudSyncChangeOperation.delete,
        revision: 2,
        contentHash: hashes[1],
        payload: null,
        deviceId: 'device-2',
        createdAt: now,
      ),
      CloudSyncChange(
        changeId: 'tombstone-page-2',
        resourceType: CloudSyncChangeResourceType.tombstone,
        resourceId: 'tombstone-page-2',
        operation: CloudSyncChangeOperation.upsert,
        revision: null,
        contentHash: null,
        payload: {
          'id': 'tombstone-page-2',
          'resourceType': 'page',
          'resourceId': 'remote-page-2',
          'baseRevision': 1,
          'resourceRevision': 1,
          'deletedRevision': 2,
          'contentHash': hashes[1],
          'content': const {'strokes': <Object?>[]},
          'structureMetadata': {'notebookId': notebook.id, 'position': 1},
          'state': 'active',
          'deletedAt': now.toIso8601String(),
          'createdAt': now.toIso8601String(),
        },
        deviceId: 'device-2',
        createdAt: now,
      ),
    ];

    final result = await SyncPageDeletionService(rootDirectory: root)
        .applyIfSafe(
          changes: changes,
          bootstrap: bootstrap,
          mappings: mappings,
          userId: 'user-1',
          deviceId: 'device-1',
        );

    expect(result?.deletedPageCount, 1);
    expect((await repository.listNotebooks()).single.pageIds, [
      localIds[0],
      localIds[2],
    ]);
    final location = await File(
      '${root.path}/sync/user-1/device-1/deleted/tombstone-page-2/location.json',
    ).readAsString();
    expect(location, contains('"position": 1'));
  });
}

CloudSyncPage _cloudPage({
  required String id,
  required String notebookId,
  required int position,
  required int revision,
  required String hash,
  required DateTime now,
}) => CloudSyncPage(
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

class _PageDeletionFixture {
  const _PageDeletionFixture({
    required this.root,
    required this.repository,
    required this.notebook,
    required this.firstPageId,
    required this.lastPageId,
    required this.bootstrap,
    required this.mappings,
  });

  final Directory root;
  final FileNotebookRepository repository;
  final Notebook notebook;
  final String firstPageId;
  final String lastPageId;
  final CloudSyncBootstrap bootstrap;
  final List<SyncResourceMapping> mappings;

  SyncPageDeletionService get service =>
      SyncPageDeletionService(rootDirectory: root);

  static Future<_PageDeletionFixture> create() async {
    final root = await Directory.systemTemp.createTemp('inknest-page-apply-');
    final repository = FileNotebookRepository(rootDirectory: root);
    var notebook = await repository.createNotebook(title: 'Two pages');
    notebook = await repository.addPage(notebook);
    final firstPageId = notebook.pageIds.first;
    final lastPageId = notebook.pageIds.last;
    final mappings = [
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, firstPageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-1',
        revision: 1,
        contentHash: 'b' * 64,
      ),
      SyncResourceMapping(
        localKey: pageSyncLocalKey(notebook.id, lastPageId),
        resourceType: SyncResourceType.page,
        remoteResourceId: 'remote-page-2',
        revision: 3,
        contentHash: 'a' * 64,
      ),
    ];
    final now = DateTime.utc(2026, 8, 7);
    final bootstrap = CloudSyncBootstrap(
      inventory: SyncLibraryInventory(notebookIds: [notebook.id]),
      baseCursor: 'bootstrap-cursor',
      folders: const [],
      notebooks: const [],
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
    return _PageDeletionFixture(
      root: root,
      repository: repository,
      notebook: notebook,
      firstPageId: firstPageId,
      lastPageId: lastPageId,
      bootstrap: bootstrap,
      mappings: mappings,
    );
  }

  List<CloudSyncChange> changes({required String deviceId}) {
    final deletedAt = DateTime.utc(2026, 8, 7);
    return [
      CloudSyncChange(
        changeId: 'delete-page-2',
        resourceType: CloudSyncChangeResourceType.page,
        resourceId: 'remote-page-2',
        operation: CloudSyncChangeOperation.delete,
        revision: 4,
        contentHash: 'a' * 64,
        payload: null,
        deviceId: deviceId,
        createdAt: deletedAt,
      ),
      CloudSyncChange(
        changeId: 'tombstone-page-2',
        resourceType: CloudSyncChangeResourceType.tombstone,
        resourceId: 'tombstone-page-2',
        operation: CloudSyncChangeOperation.upsert,
        revision: null,
        contentHash: null,
        payload: {
          'id': 'tombstone-page-2',
          'resourceType': 'page',
          'resourceId': 'remote-page-2',
          'baseRevision': 3,
          'resourceRevision': 3,
          'deletedRevision': 4,
          'contentHash': 'a' * 64,
          'content': const {'strokes': <Object?>[]},
          'structureMetadata': {'notebookId': notebook.id, 'position': 1},
          'state': 'active',
          'deletedAt': deletedAt.toIso8601String(),
          'createdAt': deletedAt.toIso8601String(),
        },
        deviceId: deviceId,
        createdAt: deletedAt,
      ),
    ];
  }

  Future<void> dispose() => root.delete(recursive: true);
}
