import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';

class SyncPageStructureResult {
  const SyncPageStructureResult({required this.restoredPageCount});

  final int restoredPageCount;
}

class SyncPageStructureService {
  const SyncPageStructureService({required this.repository});

  final NotebookRepository repository;

  Future<SyncPageStructureResult?> applyRestorationIfSafe({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
    required FileSyncResourceMapStore resourceMap,
    required Iterable<CloudSyncTombstone> changedTombstones,
  }) async {
    if (changes.isEmpty ||
        changes.any(
          (change) =>
              change.resourceType != CloudSyncChangeResourceType.page ||
              change.operation != CloudSyncChangeOperation.upsert ||
              change.revision == null ||
              change.contentHash == null,
        )) {
      return null;
    }
    final mappedRemoteIds = {
      for (final mapping in mappings)
        if (mapping.resourceType == SyncResourceType.page)
          mapping.remoteResourceId,
    };
    final additions = bootstrap.pages
        .where((page) => !mappedRemoteIds.contains(page.id))
        .toList();
    if (additions.length != 1) return null;
    final added = additions.single;
    CloudSyncTombstone? tombstone;
    for (final item in changedTombstones) {
      if (item.resourceType == 'page' &&
          item.resourceId == added.id &&
          item.state == 'restored' &&
          item.resolution == 'restored_snapshot') {
        tombstone = item;
        break;
      }
    }
    final deletedRevision = tombstone?.deletedRevision;
    final addedChange = _changeFor(changes, added.id);
    if (tombstone == null ||
        deletedRevision == null ||
        addedChange == null ||
        addedChange.revision != deletedRevision + 1 ||
        addedChange.contentHash != tombstone.contentHash ||
        added.revision != addedChange.revision ||
        added.contentHash != addedChange.contentHash) {
      return null;
    }

    final notebook = await _findLocalNotebook(added.notebookId, mappings);
    if (notebook == null || notebook.layoutMode.name != 'paged') return null;
    final cloudPages =
        bootstrap.pages
            .where((page) => page.notebookId == added.notebookId)
            .toList()
          ..sort((left, right) => left.position.compareTo(right.position));
    if (cloudPages.indexOf(added) != added.position ||
        added.position < 0 ||
        added.position > notebook.pageIds.length) {
      return null;
    }
    final localRemoteIds = <String>[];
    for (final localPageId in notebook.pageIds) {
      final mapping = _localMapping(
        mappings,
        pageSyncLocalKey(notebook.id, localPageId),
      );
      if (mapping == null || mapping.resourceType != SyncResourceType.page) {
        return null;
      }
      localRemoteIds.add(mapping.remoteResourceId);
    }
    if (!_sameOrder(
      localRemoteIds,
      cloudPages.where((page) => page.id != added.id).map((page) => page.id),
    )) {
      return null;
    }

    final unmatchedChanges = {for (final change in changes) change.resourceId};
    for (final cloud in cloudPages) {
      if (cloud.id == added.id) {
        unmatchedChanges.remove(cloud.id);
        continue;
      }
      final mapping = _remoteMapping(mappings, cloud.id);
      if (mapping == null) return null;
      final change = _changeFor(changes, cloud.id);
      if (cloud.revision == mapping.revision) {
        if (change != null) return null;
        continue;
      }
      if (change == null ||
          change.revision != mapping.revision + 1 ||
          change.contentHash != mapping.contentHash ||
          cloud.revision != change.revision ||
          cloud.contentHash != change.contentHash) {
        return null;
      }
      unmatchedChanges.remove(cloud.id);
    }
    if (unmatchedChanges.isNotEmpty) return null;

    final page = NotePage.fromJson({
      ...added.content,
      'id': added.id,
      'width': added.width,
      'height': added.height,
      'coordinateSpaceVersion': added.coordinateSpaceVersion,
      'rotationQuarterTurns': added.rotationQuarterTurns,
      'template': added.template,
    });
    final assetPaths = <String>{
      if (page.pdfBackground != null) page.pdfBackground!.assetPath,
      for (final image in page.images) image.assetPath,
    };
    for (final path in assetPaths) {
      if (!await resourceMap.hasCloudAsset(notebook.id, path)) return null;
    }

    Notebook? updated;
    try {
      updated = await repository.applySyncedPageAddition(
        notebook,
        page,
        position: added.position,
      );
    } on Object {
      if (updated != null && updated.pageIds.contains(page.id)) {
        await repository.deletePage(updated, page.id);
      }
      rethrow;
    }
    return const SyncPageStructureResult(restoredPageCount: 1);
  }

  Future<Notebook?> _findLocalNotebook(
    String remoteNotebookId,
    List<SyncResourceMapping> mappings,
  ) async {
    SyncResourceMapping? notebookMapping;
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.notebook &&
          mapping.remoteResourceId == remoteNotebookId) {
        notebookMapping = mapping;
        break;
      }
    }
    if (notebookMapping == null ||
        !notebookMapping.localKey.startsWith('notebook:')) {
      return null;
    }
    final localId = notebookMapping.localKey.substring('notebook:'.length);
    final folders = await repository.listFolders();
    final notebooks = [
      ...await repository.listNotebooks(),
      for (final folder in folders)
        ...await repository.listNotebooks(folderId: folder.id),
      ...await repository.listNotebooks(archived: true),
    ];
    for (final notebook in notebooks) {
      if (notebook.id == localId) return notebook;
    }
    return null;
  }

  CloudSyncChange? _changeFor(
    List<CloudSyncChange> changes,
    String resourceId,
  ) {
    for (final change in changes) {
      if (change.resourceId == resourceId) return change;
    }
    return null;
  }

  SyncResourceMapping? _localMapping(
    List<SyncResourceMapping> mappings,
    String localKey,
  ) {
    for (final mapping in mappings) {
      if (mapping.localKey == localKey) return mapping;
    }
    return null;
  }

  SyncResourceMapping? _remoteMapping(
    List<SyncResourceMapping> mappings,
    String remoteId,
  ) {
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.page &&
          mapping.remoteResourceId == remoteId) {
        return mapping;
      }
    }
    return null;
  }

  bool _sameOrder(Iterable<String> left, Iterable<String> right) {
    final leftItems = left.toList();
    final rightItems = right.toList();
    if (leftItems.length != rightItems.length) return false;
    for (final (index, item) in leftItems.indexed) {
      if (rightItems[index] != item) return false;
    }
    return true;
  }
}
