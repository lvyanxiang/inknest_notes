import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/shared_sync_apply_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

class SyncFolderDeletionResult {
  const SyncFolderDeletionResult({
    required this.deletedFolderCount,
    required this.confirmedLocalFolderDeletionCount,
  });

  final int deletedFolderCount;
  final int confirmedLocalFolderDeletionCount;
}

class SyncFolderDeletionService {
  const SyncFolderDeletionService({required this.repository});

  final NotebookRepository repository;

  Future<SyncFolderDeletionResult?> applyIfSafe({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
    required FileSyncResourceMapStore resourceMap,
    required String deviceId,
  }) async {
    final deletes = changes
        .where((change) => change.operation == CloudSyncChangeOperation.delete)
        .toList();
    final notebookChanges = changes
        .where(
          (change) =>
              change.operation == CloudSyncChangeOperation.upsert &&
              change.resourceType == CloudSyncChangeResourceType.notebook,
        )
        .toList();
    if (deletes.isEmpty ||
        deletes.length + notebookChanges.length != changes.length ||
        deletes.any(
          (change) =>
              change.resourceType != CloudSyncChangeResourceType.folder ||
              change.revision == null ||
              change.contentHash == null ||
              bootstrap.folders.any((folder) => folder.id == change.resourceId),
        ) ||
        deletes.map((change) => change.resourceId).toSet().length !=
            deletes.length) {
      return null;
    }

    final folders = await repository.listFolders();
    final plans = <_FolderDeletionPlan>[];
    for (final change in deletes) {
      final mapping = _mappingFor(mappings, change.resourceId);
      if (mapping == null ||
          change.revision != mapping.revision + 1 ||
          change.contentHash != mapping.contentHash) {
        return null;
      }
      NotebookFolder? folder;
      for (final candidate in folders) {
        if (mapping.localKey == folderSyncLocalKey(candidate.id)) {
          folder = candidate;
          break;
        }
      }
      final locallyDeleted = folder == null && change.deviceId == deviceId;
      if (folder == null && !locallyDeleted) return null;
      final notebooks = folder == null
          ? const <Notebook>[]
          : [
              ...await repository.listNotebooks(folderId: folder.id),
              ...await repository.listNotebooks(
                archived: true,
                folderId: folder.id,
              ),
            ];
      plans.add(
        _FolderDeletionPlan(
          folder: folder,
          notebooks: notebooks,
          locallyDeleted: locallyDeleted,
        ),
      );
    }

    final applied = <_FolderDeletionPlan>[];
    try {
      for (final plan in plans) {
        if (plan.folder case final folder?) {
          await repository.applySyncedFolderDeletion(folder);
          applied.add(plan);
        }
      }
      if (notebookChanges.isNotEmpty) {
        final shared = await SharedSyncApplyService(repository: repository)
            .applyIfSafe(
              changes: notebookChanges,
              bootstrap: bootstrap,
              mappings: mappings,
              resourceMap: resourceMap,
            );
        if (shared == null) {
          await _rollback(applied);
          return null;
        }
      }
    } on Object {
      await _rollback(applied);
      rethrow;
    }

    return SyncFolderDeletionResult(
      deletedFolderCount: plans.where((plan) => !plan.locallyDeleted).length,
      confirmedLocalFolderDeletionCount: plans
          .where((plan) => plan.locallyDeleted)
          .length,
    );
  }

  Future<void> _rollback(List<_FolderDeletionPlan> applied) async {
    for (final plan in applied.reversed) {
      await repository.applySyncedFolder(plan.folder!);
      for (final notebook in plan.notebooks) {
        await repository.applySyncedNotebookContent(notebook);
      }
    }
  }

  SyncResourceMapping? _mappingFor(
    List<SyncResourceMapping> mappings,
    String remoteFolderId,
  ) {
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.folder &&
          mapping.remoteResourceId == remoteFolderId) {
        return mapping;
      }
    }
    return null;
  }
}

class _FolderDeletionPlan {
  const _FolderDeletionPlan({
    required this.folder,
    required this.notebooks,
    required this.locallyDeleted,
  });

  final NotebookFolder? folder;
  final List<Notebook> notebooks;
  final bool locallyDeleted;
}
