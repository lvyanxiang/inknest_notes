import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';

void main() {
  group('CloudSyncBootstrap', () {
    test('parses an account inventory without notebook titles', () {
      final bootstrap = CloudSyncBootstrap.fromJson({
        'hasCloudLibrary': true,
        'folderIds': ['folder-cloud'],
        'notebookIds': ['notebook-shared', 'notebook-cloud'],
        'counts': {'folders': 1, 'notebooks': 2},
        'baseCursor': 'opaque-cursor',
      });

      expect(bootstrap.inventory.folderIds, {'folder-cloud'});
      expect(bootstrap.inventory.notebookIds, {
        'notebook-shared',
        'notebook-cloud',
      });
      expect(bootstrap.baseCursor, 'opaque-cursor');
    });

    test('rejects inconsistent or duplicate server inventory', () {
      expect(
        () => CloudSyncBootstrap.fromJson({
          'hasCloudLibrary': true,
          'folderIds': const <Object?>[],
          'notebookIds': ['duplicate', 'duplicate'],
          'counts': {'folders': 0, 'notebooks': 2},
          'baseCursor': 'opaque-cursor',
        }),
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
