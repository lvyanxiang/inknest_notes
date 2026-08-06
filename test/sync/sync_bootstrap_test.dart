import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';

void main() {
  group('CloudSyncBootstrap', () {
    test('parses the same bootstrap fixture validated by FastAPI', () async {
      final fixture = File('test/fixtures/api/v1/sync_bootstrap_response.json');
      final decoded = jsonDecode(await fixture.readAsString());

      final bootstrap = CloudSyncBootstrap.fromJson(
        (decoded! as Map<Object?, Object?>).cast<String, Object?>(),
      );

      expect(bootstrap.notebooks.length, 2);
      expect(bootstrap.pages.single.coordinateSpaceVersion, {'future': 2});
      expect(bootstrap.assets.single.id, 'asset-contract');
      expect(bootstrap.baseCursor, 'opaque-contract-cursor');
    });

    test('parses an account inventory without notebook titles', () {
      final bootstrap = CloudSyncBootstrap.fromJson(_bootstrapJson());

      expect(bootstrap.inventory.folderIds, {'folder-cloud'});
      expect(bootstrap.inventory.notebookIds, {
        'notebook-shared',
        'notebook-cloud',
      });
      expect(bootstrap.baseCursor, 'opaque-cursor');
      expect(bootstrap.pages.single.coordinateSpaceVersion, {'future': 2});
      expect(bootstrap.assets.single.sha256, 'a' * 64);
    });

    test('rejects inconsistent or duplicate server inventory', () {
      expect(
        () => CloudSyncBootstrap.fromJson(
          _bootstrapJson()
            ..['notebookIds'] = ['notebook-cloud', 'notebook-cloud'],
        ),
        throwsFormatException,
      );
    });

    test('rejects child snapshots that reference an unknown notebook', () {
      final json = _bootstrapJson();
      final page = Map<String, Object?>.from(
        (json['pages']! as List<Object?>).single! as Map<String, Object?>,
      )..['notebookId'] = 'missing-notebook';
      json['pages'] = [page];

      expect(() => CloudSyncBootstrap.fromJson(json), throwsFormatException);
    });

    test('rejects unknown folders and content in the wrong layout', () {
      final unknownFolder = _bootstrapJson();
      final notebook = Map<String, Object?>.from(
        (unknownFolder['notebooks']! as List<Object?>).first!
            as Map<String, Object?>,
      )..['folderId'] = 'missing-folder';
      unknownFolder['notebooks'] = [
        notebook,
        (unknownFolder['notebooks']! as List<Object?>).last!,
      ];
      expect(
        () => CloudSyncBootstrap.fromJson(unknownFolder),
        throwsFormatException,
      );

      final wrongLayout = _bootstrapJson();
      final page = Map<String, Object?>.from(
        (wrongLayout['pages']! as List<Object?>).single!
            as Map<String, Object?>,
      )..['notebookId'] = 'notebook-shared';
      wrongLayout['pages'] = [page];
      final canvasNotebook = Map<String, Object?>.from(
        (wrongLayout['notebooks']! as List<Object?>).first!
            as Map<String, Object?>,
      )..['layoutMode'] = 'infiniteCanvas';
      wrongLayout['notebooks'] = [
        canvasNotebook,
        (wrongLayout['notebooks']! as List<Object?>).last!,
      ];
      expect(
        () => CloudSyncBootstrap.fromJson(wrongLayout),
        throwsFormatException,
      );
    });
  });

  group('SyncBootstrapAssessment', () {
    test('distinguishes all library presence states', () {
      final empty = SyncLibraryInventory();
      final local = SyncLibraryInventory(notebookIds: ['local']);
      final cloud = SyncLibraryInventory(notebookIds: ['cloud']);

      expect(
        SyncBootstrapAssessment(local: empty, cloud: empty).presence,
        SyncLibraryPresence.empty,
      );
      expect(
        SyncBootstrapAssessment(local: local, cloud: empty).presence,
        SyncLibraryPresence.localOnly,
      );
      expect(
        SyncBootstrapAssessment(local: empty, cloud: cloud).presence,
        SyncLibraryPresence.cloudOnly,
      );
      expect(
        SyncBootstrapAssessment(local: local, cloud: cloud).presence,
        SyncLibraryPresence.localAndCloud,
      );
    });

    test('compares only stable IDs and recommends merge', () {
      final assessment = SyncBootstrapAssessment(
        local: SyncLibraryInventory(
          folderIds: ['folder-shared', 'folder-local'],
          notebookIds: ['notebook-shared', 'notebook-local'],
        ),
        cloud: SyncLibraryInventory(
          folderIds: ['folder-shared', 'folder-cloud'],
          notebookIds: ['notebook-shared', 'notebook-cloud'],
        ),
      );

      expect(assessment.presence, SyncLibraryPresence.localAndCloud);
      expect(assessment.recommendation, SyncBootstrapRecommendation.merge);
      expect(assessment.sharedNotebookIds, {'notebook-shared'});
      expect(assessment.localOnlyNotebookIds, {'notebook-local'});
      expect(assessment.cloudOnlyNotebookIds, {'notebook-cloud'});
      expect(assessment.sharedFolderIds, {'folder-shared'});
    });
  });

  test(
    'reads root, folder, and archived notebook IDs from local storage',
    () async {
      final repository = InMemoryNotebookRepository();
      final rootNotebook = await repository.createNotebook(title: 'Same title');
      final folder = await repository.createFolder('Folder');
      final folderNotebook = await repository.createNotebook(
        title: 'Same title',
      );
      await repository.moveNotebookToFolder(folderNotebook, folder.id);
      final archivedNotebook = await repository.createNotebook(
        title: 'Archive',
      );
      await repository.setNotebookArchived(archivedNotebook, true);

      final inventory = await readLocalSyncLibraryInventory(repository);

      expect(inventory.folderIds, {folder.id});
      expect(inventory.notebookIds, {
        rootNotebook.id,
        folderNotebook.id,
        archivedNotebook.id,
      });
    },
  );
}

Map<String, Object?> _bootstrapJson() {
  const timestamp = '2026-08-06T00:00:00Z';
  return {
    'hasCloudLibrary': true,
    'folderIds': ['folder-cloud'],
    'notebookIds': ['notebook-shared', 'notebook-cloud'],
    'folders': [
      {
        'id': 'folder-cloud',
        'name': 'Cloud folder',
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'notebooks': [
      for (final id in ['notebook-shared', 'notebook-cloud'])
        {
          'id': id,
          'folderId': 'folder-cloud',
          'title': 'Same display title',
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
        'width': 768.0,
        'height': 1024.0,
        'coordinateSpaceVersion': {'future': 2},
        'rotationQuarterTurns': 0,
        'template': 'blank',
        'revision': 1,
        'contentHash': 'b' * 64,
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
        'kind': 'image',
        'originalFilename': 'diagram.png',
        'contentType': 'image/png',
        'byteSize': 4,
        'sha256': 'a' * 64,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'counts': {
      'folders': 1,
      'notebooks': 2,
      'pages': 1,
      'infiniteCanvases': 0,
      'assets': 1,
    },
    'baseCursor': 'opaque-cursor',
  };
}
