import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/signed_out_sync_mutations.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

class SignedOutSyncReconciliationResult {
  const SignedOutSyncReconciliationResult({this.queuedMutationCount = 0});

  final int queuedMutationCount;
}

class SignedOutSyncReconciliationService {
  const SignedOutSyncReconciliationService({
    required this.repository,
    required this.rootDirectory,
    required this.mutationTracker,
  });

  final NotebookRepository repository;
  final Directory rootDirectory;
  final SyncMutationTracker mutationTracker;

  Future<SignedOutSyncReconciliationResult> reconcile({
    required String userId,
    required String deviceId,
  }) async {
    final stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    if ((await stateStore.loadSnapshot()).lastAppliedCursor == null) {
      return const SignedOutSyncReconciliationResult();
    }

    final intentStore = FileSignedOutSyncMutationStore(
      rootDirectory: rootDirectory,
    );
    final intents = await intentStore.loadForScope(
      userId: userId,
      deviceId: deviceId,
    );
    if (intents.isEmpty) return const SignedOutSyncReconciliationResult();

    final mappings = {
      for (final mapping in await FileSyncResourceMapStore(
        rootDirectory: rootDirectory,
        userId: userId,
        deviceId: deviceId,
      ).load())
        mapping.localKey: mapping,
    };
    final folders = {
      for (final folder in await repository.listFolders()) folder.id: folder,
    };
    final notebooks = await _loadAllNotebooks(folders.values);
    final deletedNotebookIds = <String>{};
    var queuedCount = 0;

    final ordered = intents.toList()
      ..sort((left, right) {
        final leftPriority = _priority(left);
        final rightPriority = _priority(right);
        if (leftPriority != rightPriority) {
          return leftPriority.compareTo(rightPriority);
        }
        return left.localKey.compareTo(right.localKey);
      });

    for (final intent in ordered) {
      final mapping = mappings[intent.localKey];
      if (mapping == null) continue;
      final notebookId = _notebookIdFromLocalKey(intent.localKey);
      if (notebookId != null && deletedNotebookIds.contains(notebookId)) {
        await intentStore.consume(
          localKey: intent.localKey,
          userId: userId,
          deviceId: deviceId,
        );
        continue;
      }

      final queued = intent.kind == SignedOutSyncMutationKind.delete
          ? await _queueDelete(
              intent: intent,
              mapping: mapping,
              stateStore: stateStore,
              deletedNotebookIds: deletedNotebookIds,
            )
          : await _queueUpsert(
              intent: intent,
              mapping: mapping,
              mappings: mappings,
              folders: folders,
              notebooks: notebooks,
            );
      if (!queued) continue;
      await intentStore.consume(
        localKey: intent.localKey,
        userId: userId,
        deviceId: deviceId,
      );
      queuedCount++;
    }

    return SignedOutSyncReconciliationResult(queuedMutationCount: queuedCount);
  }

  Future<bool> _queueDelete({
    required SignedOutSyncMutation intent,
    required SyncResourceMapping mapping,
    required FileSyncStateStore stateStore,
    required Set<String> deletedNotebookIds,
  }) async {
    if (mapping.resourceType == SyncResourceType.infiniteCanvas) {
      return false;
    }
    await stateStore.enqueueDelete(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
    );
    if (mapping.resourceType == SyncResourceType.notebook) {
      final notebookId = _notebookIdFromLocalKey(intent.localKey);
      if (notebookId != null) deletedNotebookIds.add(notebookId);
    }
    return true;
  }

  Future<bool> _queueUpsert({
    required SignedOutSyncMutation intent,
    required SyncResourceMapping mapping,
    required Map<String, SyncResourceMapping> mappings,
    required Map<String, NotebookFolder> folders,
    required Map<String, Notebook> notebooks,
  }) async {
    switch (mapping.resourceType) {
      case SyncResourceType.folder:
        if (!intent.localKey.startsWith('folder:') ||
            mapping.folderMetadata == null) {
          return false;
        }
        final folder = folders[_suffix(intent.localKey, 'folder:')];
        if (folder == null) return false;
        await mutationTracker.folderSaved(folder);
        return true;
      case SyncResourceType.notebook:
        if (!intent.localKey.startsWith('notebook:') ||
            mapping.notebookMetadata == null) {
          return false;
        }
        final notebook = notebooks[_suffix(intent.localKey, 'notebook:')];
        if (notebook == null || !_allPagesMapped(notebook, mappings)) {
          return false;
        }
        await mutationTracker.notebookMetadataSaved(notebook);
        await mutationTracker.notebookContentSaved(notebook);
        return true;
      case SyncResourceType.page:
        final parts = _pageParts(intent.localKey);
        if (parts == null) return false;
        final notebook = notebooks[parts.$1];
        if (notebook == null || !notebook.pageIds.contains(parts.$2)) {
          return false;
        }
        await mutationTracker.pageSaved(
          notebook,
          await repository.loadPage(notebook, parts.$2),
        );
        return true;
      case SyncResourceType.infiniteCanvas:
        if (!intent.localKey.startsWith('infinite_canvas:') ||
            mapping.infiniteCanvasMetadata == null) {
          return false;
        }
        final notebook =
            notebooks[_suffix(intent.localKey, 'infinite_canvas:')];
        if (notebook == null ||
            notebook.layoutMode != NotebookLayoutMode.infiniteCanvas) {
          return false;
        }
        await mutationTracker.infiniteCanvasSaved(
          notebook,
          await repository.loadInfiniteCanvas(notebook),
        );
        return true;
    }
  }

  bool _allPagesMapped(
    Notebook notebook,
    Map<String, SyncResourceMapping> mappings,
  ) {
    // Notebook metadata/content tracking already performs the authoritative
    // resource-map check. This preflight avoids consuming an intent when a
    // newly added page still needs its own creation contract.
    return notebook.layoutMode == NotebookLayoutMode.infiniteCanvas ||
        notebook.pageIds.every(
          (pageId) =>
              mappings[pageSyncLocalKey(notebook.id, pageId)]?.resourceType ==
              SyncResourceType.page,
        );
  }

  Future<Map<String, Notebook>> _loadAllNotebooks(
    Iterable<NotebookFolder> folders,
  ) async => {
    for (final notebook in await repository.listNotebooks())
      notebook.id: notebook,
    for (final folder in folders)
      for (final notebook in await repository.listNotebooks(
        folderId: folder.id,
      ))
        notebook.id: notebook,
    for (final notebook in await repository.listNotebooks(archived: true))
      notebook.id: notebook,
  };
}

int _priority(SignedOutSyncMutation mutation) {
  if (mutation.kind == SignedOutSyncMutationKind.delete) {
    if (mutation.localKey.startsWith('notebook:')) return 0;
    if (mutation.localKey.startsWith('folder:')) return 1;
    return 2;
  }
  if (mutation.localKey.startsWith('folder:')) return 3;
  if (mutation.localKey.startsWith('notebook:')) return 4;
  if (mutation.localKey.startsWith('page:')) return 5;
  return 6;
}

String? _notebookIdFromLocalKey(String localKey) {
  if (localKey.startsWith('notebook:')) {
    return _suffix(localKey, 'notebook:');
  }
  if (localKey.startsWith('infinite_canvas:')) {
    return _suffix(localKey, 'infinite_canvas:');
  }
  return _pageParts(localKey)?.$1;
}

(String, String)? _pageParts(String localKey) {
  if (!localKey.startsWith('page:')) return null;
  final separator = localKey.indexOf(':', 'page:'.length);
  if (separator == -1 || separator == localKey.length - 1) return null;
  return (
    localKey.substring('page:'.length, separator),
    localKey.substring(separator + 1),
  );
}

String _suffix(String value, String prefix) => value.substring(prefix.length);
