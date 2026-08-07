import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';

void main() {
  late Directory rootDirectory;
  late FileNotebookRepository repository;
  late FileSyncStateStore stateStore;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp(
      'inknest-bootstrap-restore-',
    );
    repository = FileNotebookRepository(rootDirectory: rootDirectory);
    stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: 'user-1',
      deviceId: 'device-1',
    );
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  test(
    'cloud-only bootstrap verifies bytes, applies, then saves Cursor',
    () async {
      final bytes = [1, 2, 3, 4];
      final bootstrap = _bootstrap(bytes);
      final assessment = SyncBootstrapAssessment(
        local: SyncLibraryInventory(),
        cloud: bootstrap.inventory,
      );
      final service = _createService(
        rootDirectory,
        stateStore,
        _FakeAssetClient(bytes),
      );

      final result = await service.downloadAndApplyCloudOnly(
        bootstrap: bootstrap,
        assessment: assessment,
        persistCursor: true,
      );

      final notebooks = await repository.listNotebooks(
        folderId: 'folder-cloud',
      );
      expect(result.downloadedNotebookCount, 1);
      expect(result.downloadedAssetCount, 1);
      expect(result.cursorPersisted, isTrue);
      expect(notebooks.single.id, 'notebook-cloud');
      expect(
        (await repository.loadPage(notebooks.single, 'page-cloud')).strokes,
        isEmpty,
      );
      expect(
        await File(
          '${rootDirectory.path}/notebooks/notebook-cloud/assets/imported.pdf',
        ).readAsBytes(),
        bytes,
      );
      expect(
        (await stateStore.loadSnapshot()).lastAppliedCursor,
        'bootstrap-cursor',
      );
    },
  );

  test(
    'failed asset verification leaves the local library untouched',
    () async {
      final local = await repository.createNotebook(title: 'Local notebook');
      final bootstrap = _bootstrap([1, 2, 3, 4]);
      final localInventory = await readLocalSyncLibraryInventory(repository);
      final service = _createService(
        rootDirectory,
        stateStore,
        _FakeAssetClient([9, 9]),
      );

      await expectLater(
        service.downloadAndApplyCloudOnly(
          bootstrap: bootstrap,
          assessment: SyncBootstrapAssessment(
            local: localInventory,
            cloud: bootstrap.inventory,
          ),
          persistCursor: false,
        ),
        throwsA(isA<BootstrapAssetVerificationException>()),
      );

      expect((await repository.listNotebooks()).single.id, local.id);
      expect(
        await Directory(
          '${rootDirectory.path}/notebooks/notebook-cloud',
        ).exists(),
        isFalse,
      );
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, isNull);
    },
  );

  test(
    'can defer Cursor until the caller completes handoff metadata',
    () async {
      final bytes = [1, 2, 3, 4];
      final bootstrap = _bootstrap(bytes);
      final service = _createService(
        rootDirectory,
        stateStore,
        _FakeAssetClient(bytes),
      );

      final result = await service.downloadAndApplyCloudOnly(
        bootstrap: bootstrap,
        assessment: SyncBootstrapAssessment(
          local: SyncLibraryInventory(),
          cloud: bootstrap.inventory,
        ),
        persistCursor: false,
      );

      expect(result.downloadedNotebookCount, 1);
      expect(result.cursorPersisted, isFalse);
      expect(
        (await repository.listNotebooks(folderId: 'folder-cloud')),
        hasLength(1),
      );
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, isNull);
    },
  );

  test(
    'an apply failure rolls back indexes and newly moved directories',
    () async {
      final local = await repository.createNotebook(title: 'Local notebook');
      final bootstrap = _bootstrap([1, 2, 3, 4]);
      final localInventory = await readLocalSyncLibraryInventory(repository);
      final service = _createService(
        rootDirectory,
        stateStore,
        _FakeAssetClient([1, 2, 3, 4]),
        checkpoint: (checkpoint) async {
          if (checkpoint == 'foldersWritten') {
            throw StateError('simulated storage failure');
          }
        },
      );

      await expectLater(
        service.downloadAndApplyCloudOnly(
          bootstrap: bootstrap,
          assessment: SyncBootstrapAssessment(
            local: localInventory,
            cloud: bootstrap.inventory,
          ),
          persistCursor: false,
        ),
        throwsStateError,
      );

      expect((await repository.listNotebooks()).single.id, local.id);
      expect(await repository.listFolders(), isEmpty);
      expect(
        await Directory(
          '${rootDirectory.path}/notebooks/notebook-cloud',
        ).exists(),
        isFalse,
      );
      expect((await stateStore.loadSnapshot()).lastAppliedCursor, isNull);
    },
  );
}

BootstrapRestoreService _createService(
  Directory rootDirectory,
  FileSyncStateStore stateStore,
  CloudAssetTransferClient client, {
  BootstrapApplyCheckpoint? checkpoint,
}) {
  return BootstrapRestoreService(
    rootDirectory: rootDirectory,
    assetClient: client,
    syncStateStore: stateStore,
    clock: () => DateTime.utc(2026, 8, 6),
    random: Random(1),
    checkpoint: checkpoint,
  );
}

class _FakeAssetClient implements CloudAssetTransferClient {
  const _FakeAssetClient(this.bytes);

  final List<int> bytes;

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) async {
    return CloudAssetDownload(
      assetId: assetId,
      filename: 'lesson.pdf',
      relativePath: 'assets/imported.pdf',
      contentType: 'application/pdf',
      byteSize: 4,
      sha256: sha256.convert([1, 2, 3, 4]).toString(),
      downloadUrl: Uri.parse('https://objects.example.com/asset-cloud'),
      expiresAt: DateTime.utc(2026, 8, 6, 0, 5),
    );
  }

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) async {
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
  }
}

CloudSyncBootstrap _bootstrap(List<int> expectedBytes) {
  const timestamp = '2026-08-06T00:00:00Z';
  return CloudSyncBootstrap.fromJson({
    'hasCloudLibrary': true,
    'folderIds': ['folder-cloud'],
    'notebookIds': ['notebook-cloud'],
    'folders': [
      {
        'id': 'folder-cloud',
        'name': 'Cloud folder',
        'revision': 0,
        'contentHash': '',
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'notebooks': [
      {
        'id': 'notebook-cloud',
        'folderId': 'folder-cloud',
        'title': 'Cloud notebook',
        'layoutMode': 'paged',
        'isArchived': false,
        'revision': 0,
        'contentHash': '',
        'content': <String, Object?>{},
        'conflictOf': null,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'pages': [
      {
        'id': 'page-cloud',
        'notebookId': 'notebook-cloud',
        'position': 0,
        'width': 768,
        'height': 1024,
        'coordinateSpaceVersion': 1,
        'rotationQuarterTurns': 0,
        'template': 'blank',
        'revision': 1,
        'contentHash': 'a' * 64,
        'content': {'strokes': <Object?>[]},
        'conflictOf': null,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'infiniteCanvases': <Object?>[],
    'assets': [
      {
        'id': 'asset-cloud',
        'notebookId': 'notebook-cloud',
        'kind': 'pdf',
        'originalFilename': 'lesson.pdf',
        'relativePath': 'assets/imported.pdf',
        'contentType': 'application/pdf',
        'byteSize': expectedBytes.length,
        'sha256': sha256.convert(expectedBytes).toString(),
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'counts': {
      'folders': 1,
      'notebooks': 1,
      'pages': 1,
      'infiniteCanvases': 0,
      'assets': 1,
    },
    'baseCursor': 'bootstrap-cursor',
  });
}
