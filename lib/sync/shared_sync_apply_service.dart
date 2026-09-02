import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

class SharedSyncApplyResult {
  const SharedSyncApplyResult({required this.appliedResourceCount});

  final int appliedResourceCount;
}

class SharedSyncAtomicApplyException extends StateError {
  SharedSyncAtomicApplyException(super.message);
}

class SharedSyncApplyService {
  const SharedSyncApplyService({required this.repository});

  final NotebookRepository repository;

  Future<SharedSyncApplyResult?> applyIfSafe({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
    required FileSyncResourceMapStore resourceMap,
  }) async {
    if (changes.any(
      (change) =>
          change.operation != CloudSyncChangeOperation.upsert ||
          !const {
            CloudSyncChangeResourceType.folder,
            CloudSyncChangeResourceType.notebook,
            CloudSyncChangeResourceType.page,
            CloudSyncChangeResourceType.infiniteCanvas,
          }.contains(change.resourceType) ||
          change.revision == null ||
          change.contentHash == null,
    )) {
      return null;
    }

    final notebooks = await _allNotebooks();
    final folders = await repository.listFolders();
    final folderIds = folders.map((folder) => folder.id).toSet();
    final changesByResource = <String, List<CloudSyncChange>>{};
    for (final change in changes) {
      changesByResource.putIfAbsent(_remoteKey(change), () => []).add(change);
    }
    final pageOrderPreparation = _preparePageOrderActions(
      changesByResource: changesByResource,
      bootstrap: bootstrap,
      notebooks: notebooks,
      mappings: mappings,
    );
    if (pageOrderPreparation == null) return null;
    final actions = <_SharedApplyAction>[...pageOrderPreparation.actions];
    for (final entry in changesByResource.entries) {
      final first = entry.value.first;
      final mapping = _findRemoteMapping(mappings, first);
      final snapshot = _snapshotFor(first, bootstrap);
      if (snapshot == null) {
        return null;
      }
      if (mapping == null) {
        if (first.resourceType == CloudSyncChangeResourceType.folder &&
            snapshot is _FolderSharedSnapshot) {
          final local = _findFolder(folders, first.resourceId);
          if (local == null ||
              local.name != snapshot.value.name ||
              !_hasContinuousNewRevisionChain(entry.value) ||
              snapshot.revision != entry.value.last.revision ||
              snapshot.contentHash != entry.value.last.contentHash) {
            return null;
          }
          actions.add(_folderAction(local, snapshot.value));
          continue;
        }
        final addition = await _buildNewPageAction(
          first: first,
          changes: entry.value,
          snapshot: snapshot,
          notebooks: notebooks,
          mappings: mappings,
          resourceMap: resourceMap,
        );
        if (addition == null) return null;
        actions.add(addition);
        continue;
      }
      if (!_hasContinuousRevisionChain(mapping, entry.value) ||
          snapshot.revision != _finalRevision(mapping, entry.value) ||
          snapshot.contentHash != _finalHash(mapping, entry.value)) {
        return null;
      }
      if (mapping.revision == snapshot.revision) continue;
      final action = await _buildAction(
        mapping: mapping,
        snapshot: snapshot,
        notebooks: notebooks,
        mappings: mappings,
        resourceMap: resourceMap,
        folderIds: folderIds,
        folders: folders,
        expectedPagePositions: pageOrderPreparation.expectedPagePositions,
        expectedPageOrders: pageOrderPreparation.expectedPageOrders,
      );
      if (action == null) return null;
      actions.add(action);
    }

    final applied = <_SharedApplyAction>[];
    try {
      for (final action in actions) {
        await action.apply();
        applied.add(action);
      }
    } on Object {
      try {
        for (final action in applied.reversed) {
          await action.rollback();
        }
      } on Object {
        throw SharedSyncAtomicApplyException(
          'Shared synchronization failed and local rollback was incomplete.',
        );
      }
      rethrow;
    }
    return SharedSyncApplyResult(appliedResourceCount: actions.length);
  }

  _PageOrderPreparation? _preparePageOrderActions({
    required Map<String, List<CloudSyncChange>> changesByResource,
    required CloudSyncBootstrap bootstrap,
    required List<Notebook> notebooks,
    required List<SyncResourceMapping> mappings,
  }) {
    final actions = <_SharedApplyAction>[];
    final expectedPagePositions = <String, int>{};
    final expectedPageOrders = <String, List<String>>{};
    for (final notebook in notebooks) {
      if (notebook.layoutMode.name != 'paged') continue;
      final notebookMapping = _findLocalMapping(
        mappings,
        notebookSyncLocalKey(notebook.id),
      );
      if (notebookMapping == null ||
          notebookMapping.resourceType != SyncResourceType.notebook) {
        continue;
      }
      final cloudPages =
          bootstrap.pages
              .where(
                (page) => page.notebookId == notebookMapping.remoteResourceId,
              )
              .toList()
            ..sort((left, right) => left.position.compareTo(right.position));
      final localByRemote = <String, String>{};
      final currentRemoteOrder = <String>[];
      var hasCompletePageMappings = true;
      for (final localPageId in notebook.pageIds) {
        final mapping = _findLocalMapping(
          mappings,
          pageSyncLocalKey(notebook.id, localPageId),
        );
        if (mapping == null || mapping.resourceType != SyncResourceType.page) {
          hasCompletePageMappings = false;
          break;
        }
        currentRemoteOrder.add(mapping.remoteResourceId);
        localByRemote[mapping.remoteResourceId] = localPageId;
      }
      if (!hasCompletePageMappings) continue;
      final desiredRemoteOrder = cloudPages.map((page) => page.id).toList();
      if (_sameOrder(currentRemoteOrder, desiredRemoteOrder)) continue;
      if (currentRemoteOrder.length != desiredRemoteOrder.length ||
          currentRemoteOrder.toSet().length != currentRemoteOrder.length ||
          currentRemoteOrder.toSet().containsAll(desiredRemoteOrder) == false) {
        continue;
      }

      for (final (position, cloudPage) in cloudPages.indexed) {
        final localPageId = localByRemote[cloudPage.id];
        if (localPageId == null) return null;
        final localKey = pageSyncLocalKey(notebook.id, localPageId);
        expectedPagePositions[localKey] = position;
        if (currentRemoteOrder[position] == cloudPage.id) continue;
        final mapping = _findLocalMapping(mappings, localKey)!;
        final pageChanges =
            changesByResource['${CloudSyncChangeResourceType.page.apiValue}\u0000${cloudPage.id}'];
        if (pageChanges == null ||
            !_hasContinuousRevisionChain(mapping, pageChanges) ||
            cloudPage.revision != _finalRevision(mapping, pageChanges) ||
            cloudPage.contentHash != _finalHash(mapping, pageChanges) ||
            !pageChanges.any(
              (change) =>
                  change.revision == mapping.revision + 1 &&
                  change.contentHash == mapping.contentHash,
            )) {
          return null;
        }
      }

      CloudSyncNotebook? cloudNotebook;
      for (final candidate in bootstrap.notebooks) {
        if (candidate.id == notebookMapping.remoteResourceId) {
          cloudNotebook = candidate;
          break;
        }
      }
      final notebookChanges =
          changesByResource['${CloudSyncChangeResourceType.notebook.apiValue}\u0000${notebookMapping.remoteResourceId}'];
      if (cloudNotebook == null ||
          notebookChanges == null ||
          !_hasContinuousRevisionChain(notebookMapping, notebookChanges) ||
          cloudNotebook.revision !=
              _finalRevision(notebookMapping, notebookChanges) ||
          cloudNotebook.contentHash !=
              _finalHash(notebookMapping, notebookChanges)) {
        return null;
      }

      final desiredLocalOrder = [
        for (final remoteId in desiredRemoteOrder) localByRemote[remoteId]!,
      ];
      expectedPageOrders[notebook.id] = desiredLocalOrder;
      Notebook? appliedNotebook;
      actions.add(
        _SharedApplyAction(
          apply: () async {
            appliedNotebook = await repository.applySyncedPageOrder(
              notebook,
              desiredLocalOrder,
            );
          },
          rollback: () async {
            await repository.applySyncedPageOrder(
              appliedNotebook ?? notebook,
              notebook.pageIds,
            );
          },
        ),
      );
    }
    return _PageOrderPreparation(
      actions: actions,
      expectedPagePositions: expectedPagePositions,
      expectedPageOrders: expectedPageOrders,
    );
  }

  bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (final (index, item) in left.indexed) {
      if (right[index] != item) return false;
    }
    return true;
  }

  Future<_SharedApplyAction?> _buildNewPageAction({
    required CloudSyncChange first,
    required List<CloudSyncChange> changes,
    required _SharedSnapshot snapshot,
    required List<Notebook> notebooks,
    required List<SyncResourceMapping> mappings,
    required FileSyncResourceMapStore resourceMap,
  }) async {
    if (first.resourceType != CloudSyncChangeResourceType.page ||
        snapshot is! _PageSharedSnapshot ||
        !_hasContinuousNewRevisionChain(changes) ||
        snapshot.revision != changes.last.revision ||
        snapshot.contentHash != changes.last.contentHash) {
      return null;
    }
    final cloud = snapshot.value;
    final notebook = _findNotebook(notebooks, cloud.notebookId);
    final alreadyApplied =
        cloud.position < (notebook?.pageIds.length ?? 0) &&
        notebook?.pageIds[cloud.position] == cloud.id;
    if (notebook == null ||
        notebook.layoutMode.name != 'paged' ||
        (cloud.position != notebook.pageIds.length && !alreadyApplied) ||
        (notebook.pageIds.contains(cloud.id) && !alreadyApplied) ||
        _findRemoteNotebookMapping(mappings, cloud.notebookId) == null) {
      return null;
    }
    final page = NotePage.fromJson({
      ...cloud.content,
      'id': cloud.id,
      'width': cloud.width,
      'height': cloud.height,
      'coordinateSpaceVersion': cloud.coordinateSpaceVersion,
      'rotationQuarterTurns': cloud.rotationQuarterTurns,
      'template': cloud.template,
    });
    if (!await _pageAssetsAreKnown(notebook, page, resourceMap)) return null;

    Notebook? appliedNotebook;
    final shouldAppend = !alreadyApplied;
    return _SharedApplyAction(
      apply: () async {
        appliedNotebook = await repository.applySyncedPageAddition(
          notebook,
          page,
        );
      },
      rollback: () async {
        final applied = appliedNotebook;
        if (shouldAppend && applied != null) {
          await repository.deletePage(applied, page.id);
        }
      },
    );
  }

  bool _hasContinuousNewRevisionChain(List<CloudSyncChange> changes) {
    var revision = 0;
    for (final change in changes) {
      final nextRevision = change.revision;
      if (nextRevision == null || nextRevision != revision + 1) return false;
      revision = nextRevision;
    }
    return true;
  }

  bool _hasContinuousRevisionChain(
    SyncResourceMapping mapping,
    List<CloudSyncChange> changes,
  ) {
    var revision = mapping.revision;
    var contentHash = mapping.contentHash;
    for (final change in changes) {
      final nextRevision = change.revision!;
      final nextHash = change.contentHash!;
      if (nextRevision < revision) continue;
      if (nextRevision == revision) {
        if (nextHash != contentHash) return false;
        continue;
      }
      if (nextRevision != revision + 1) return false;
      revision = nextRevision;
      contentHash = nextHash;
    }
    return true;
  }

  int _finalRevision(
    SyncResourceMapping mapping,
    List<CloudSyncChange> changes,
  ) => changes.fold(
    mapping.revision,
    (revision, change) =>
        change.revision! > revision ? change.revision! : revision,
  );

  String _finalHash(
    SyncResourceMapping mapping,
    List<CloudSyncChange> changes,
  ) {
    var revision = mapping.revision;
    var hash = mapping.contentHash;
    for (final change in changes) {
      if (change.revision! > revision) {
        revision = change.revision!;
        hash = change.contentHash!;
      }
    }
    return hash;
  }

  _SharedSnapshot? _snapshotFor(
    CloudSyncChange change,
    CloudSyncBootstrap bootstrap,
  ) {
    return switch (change.resourceType) {
      CloudSyncChangeResourceType.notebook => _findSnapshot(
        bootstrap.notebooks,
        change.resourceId,
        (item) => item.id,
        (item) => _SharedSnapshot.notebook(item),
      ),
      CloudSyncChangeResourceType.page => _findSnapshot(
        bootstrap.pages,
        change.resourceId,
        (item) => item.id,
        (item) => _SharedSnapshot.page(item),
      ),
      CloudSyncChangeResourceType.infiniteCanvas => _findSnapshot(
        bootstrap.infiniteCanvases,
        change.resourceId,
        (item) => item.id,
        (item) => _SharedSnapshot.canvas(item),
      ),
      CloudSyncChangeResourceType.folder => _findSnapshot(
        bootstrap.folders,
        change.resourceId,
        (item) => item.id,
        (item) => _SharedSnapshot.folder(item),
      ),
      _ => null,
    };
  }

  TOutput? _findSnapshot<TInput, TOutput>(
    Iterable<TInput> items,
    String id,
    String Function(TInput item) idOf,
    TOutput Function(TInput item) convert,
  ) {
    for (final item in items) {
      if (idOf(item) == id) return convert(item);
    }
    return null;
  }

  Future<_SharedApplyAction?> _buildAction({
    required SyncResourceMapping mapping,
    required _SharedSnapshot snapshot,
    required List<Notebook> notebooks,
    required List<SyncResourceMapping> mappings,
    required FileSyncResourceMapStore resourceMap,
    required Set<String> folderIds,
    required List<NotebookFolder> folders,
    required Map<String, int> expectedPagePositions,
    required Map<String, List<String>> expectedPageOrders,
  }) {
    return switch (snapshot) {
      _FolderSharedSnapshot() => _buildFolderAction(
        mapping,
        snapshot.value,
        folders,
      ),
      _NotebookSharedSnapshot() => _buildNotebookAction(
        mapping,
        snapshot.value,
        notebooks,
        mappings,
        resourceMap,
        folderIds,
        expectedPageOrders,
      ),
      _PageSharedSnapshot() => _buildPageAction(
        mapping,
        snapshot.value,
        notebooks,
        mappings,
        resourceMap,
        expectedPagePositions,
      ),
      _CanvasSharedSnapshot() => _buildCanvasAction(
        mapping,
        snapshot.value,
        notebooks,
        resourceMap,
      ),
    };
  }

  Future<_SharedApplyAction?> _buildFolderAction(
    SyncResourceMapping mapping,
    CloudSyncFolder cloud,
    List<NotebookFolder> folders,
  ) async {
    final local = _findFolder(folders, cloud.id);
    if (local == null || mapping.localKey != folderSyncLocalKey(local.id)) {
      return null;
    }
    return _folderAction(local, cloud);
  }

  _SharedApplyAction _folderAction(
    NotebookFolder local,
    CloudSyncFolder cloud,
  ) {
    final updated = NotebookFolder(
      id: local.id,
      name: cloud.name,
      createdAt: cloud.createdAt,
      updatedAt: cloud.updatedAt,
    );
    return _SharedApplyAction(
      apply: () => repository.applySyncedFolder(updated),
      rollback: () => repository.applySyncedFolder(local),
    );
  }

  Future<_SharedApplyAction?> _buildNotebookAction(
    SyncResourceMapping mapping,
    CloudSyncNotebook cloud,
    List<Notebook> notebooks,
    List<SyncResourceMapping> mappings,
    FileSyncResourceMapStore resourceMap,
    Set<String> folderIds,
    Map<String, List<String>> expectedPageOrders,
  ) async {
    final local = _findNotebook(notebooks, cloud.id);
    if (local == null ||
        mapping.localKey != notebookSyncLocalKey(local.id) ||
        (cloud.folderId != null && !folderIds.contains(cloud.folderId)) ||
        cloud.layoutMode != local.layoutMode.name) {
      return null;
    }
    final remoteToLocalPageIds = <String, String>{};
    for (final pageId in local.pageIds) {
      final pageMapping = _findLocalMapping(
        mappings,
        pageSyncLocalKey(local.id, pageId),
      );
      if (pageMapping != null) {
        remoteToLocalPageIds[pageMapping.remoteResourceId] = pageId;
      }
    }
    final content =
        _rewritePageReferences(cloud.content, remoteToLocalPageIds)!
            as Map<String, Object?>;
    final updated = Notebook.fromJson({
      ...content,
      'id': local.id,
      'title': cloud.title,
      'createdAt': local.createdAt.toIso8601String(),
      'updatedAt': cloud.updatedAt.toIso8601String(),
      'pageIds': expectedPageOrders[local.id] ?? local.pageIds,
      'isArchived': cloud.isArchived,
      if (cloud.folderId != null) 'folderId': cloud.folderId,
      'layoutMode': local.layoutMode.name,
    });
    if (!_notebookReferencesAreLocal(updated) ||
        !await _notebookAssetsAreKnown(updated, resourceMap)) {
      return null;
    }
    return _SharedApplyAction(
      apply: () async {
        await repository.applySyncedNotebookContent(updated);
      },
      rollback: () async {
        await repository.applySyncedNotebookContent(local);
      },
    );
  }

  Future<_SharedApplyAction?> _buildPageAction(
    SyncResourceMapping mapping,
    CloudSyncPage cloud,
    List<Notebook> notebooks,
    List<SyncResourceMapping> mappings,
    FileSyncResourceMapStore resourceMap,
    Map<String, int> expectedPagePositions,
  ) async {
    for (final notebook in notebooks) {
      for (final (position, pageId) in notebook.pageIds.indexed) {
        if (mapping.localKey != pageSyncLocalKey(notebook.id, pageId)) continue;
        final expectedPosition =
            expectedPagePositions[mapping.localKey] ?? position;
        if (cloud.notebookId != notebook.id ||
            cloud.position != expectedPosition) {
          return null;
        }
        final local = await repository.loadPage(notebook, pageId);
        final updated = NotePage.fromJson({
          ...cloud.content,
          'id': local.id,
          'width': cloud.width,
          'height': cloud.height,
          'coordinateSpaceVersion': cloud.coordinateSpaceVersion,
          'rotationQuarterTurns': cloud.rotationQuarterTurns,
          'template': cloud.template,
        });
        if (!await _pageAssetsAreKnown(notebook, updated, resourceMap)) {
          return null;
        }
        return _SharedApplyAction(
          apply: () => repository.applySyncedPage(notebook, updated),
          rollback: () => repository.applySyncedPage(notebook, local),
        );
      }
    }
    return null;
  }

  Future<_SharedApplyAction?> _buildCanvasAction(
    SyncResourceMapping mapping,
    CloudSyncInfiniteCanvas cloud,
    List<Notebook> notebooks,
    FileSyncResourceMapStore resourceMap,
  ) async {
    for (final notebook in notebooks) {
      if (mapping.localKey != canvasSyncLocalKey(notebook.id)) continue;
      final local = await repository.loadInfiniteCanvas(notebook);
      InfiniteCanvasBackground? background;
      for (final candidate in InfiniteCanvasBackground.values) {
        if (candidate.name == cloud.background) {
          background = candidate;
          break;
        }
      }
      if (cloud.notebookId != notebook.id || background == null) {
        return null;
      }
      final updated = InfiniteCanvasDocument.fromJson({
        ...cloud.content,
        'background': background.name,
      });
      for (final image in updated.images) {
        if (!await resourceMap.hasCloudAsset(notebook.id, image.assetPath)) {
          return null;
        }
      }
      return _SharedApplyAction(
        apply: () => repository.saveInfiniteCanvas(notebook, updated),
        rollback: () => repository.saveInfiniteCanvas(notebook, local),
      );
    }
    return null;
  }

  Future<List<Notebook>> _allNotebooks() async {
    final folders = await repository.listFolders();
    return [
      ...await repository.listNotebooks(),
      for (final folder in folders)
        ...await repository.listNotebooks(folderId: folder.id),
      ...await repository.listNotebooks(archived: true),
    ];
  }

  SyncResourceMapping? _findRemoteMapping(
    List<SyncResourceMapping> mappings,
    CloudSyncChange change,
  ) {
    final type = switch (change.resourceType) {
      CloudSyncChangeResourceType.notebook => SyncResourceType.notebook,
      CloudSyncChangeResourceType.folder => SyncResourceType.folder,
      CloudSyncChangeResourceType.page => SyncResourceType.page,
      CloudSyncChangeResourceType.infiniteCanvas =>
        SyncResourceType.infiniteCanvas,
      _ => null,
    };
    if (type == null) return null;
    for (final mapping in mappings) {
      if (mapping.resourceType == type &&
          mapping.remoteResourceId == change.resourceId) {
        return mapping;
      }
    }
    return null;
  }

  SyncResourceMapping? _findLocalMapping(
    List<SyncResourceMapping> mappings,
    String localKey,
  ) {
    for (final mapping in mappings) {
      if (mapping.localKey == localKey) return mapping;
    }
    return null;
  }

  SyncResourceMapping? _findRemoteNotebookMapping(
    List<SyncResourceMapping> mappings,
    String notebookId,
  ) {
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.notebook &&
          mapping.remoteResourceId == notebookId) {
        return mapping;
      }
    }
    return null;
  }

  Notebook? _findNotebook(List<Notebook> notebooks, String id) {
    for (final notebook in notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  NotebookFolder? _findFolder(List<NotebookFolder> folders, String id) {
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  bool _notebookReferencesAreLocal(Notebook notebook) {
    final pageIds = notebook.pageIds.toSet();
    final references = <String>{...notebook.bookmarkedPageIds};
    void addOutlines(Iterable<PdfOutlineEntry> outlines) {
      for (final outline in outlines) {
        if (outline.pageId case final String pageId) references.add(pageId);
        addOutlines(outline.children);
      }
    }

    addOutlines(notebook.pdfOutlines);
    for (final recording in notebook.audioRecordings) {
      if (recording.pageId case final String pageId) references.add(pageId);
    }
    return pageIds.containsAll(references);
  }

  Future<bool> _notebookAssetsAreKnown(
    Notebook notebook,
    FileSyncResourceMapStore resourceMap,
  ) async {
    for (final recording in notebook.audioRecordings) {
      if (!await resourceMap.hasCloudAsset(notebook.id, recording.assetPath)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _pageAssetsAreKnown(
    Notebook notebook,
    NotePage page,
    FileSyncResourceMapStore resourceMap,
  ) async {
    final paths = <String>{
      if (page.pdfBackground != null) page.pdfBackground!.assetPath,
      for (final image in page.images) image.assetPath,
    };
    for (final path in paths) {
      if (!await resourceMap.hasCloudAsset(notebook.id, path)) return false;
    }
    return true;
  }

  String _remoteKey(CloudSyncChange change) =>
      '${change.resourceType.apiValue}\u0000${change.resourceId}';

  Object? _rewritePageReferences(
    Object? value,
    Map<String, String> remoteToLocalPageIds, {
    String? key,
  }) {
    if (key == 'pageId' && value is String) {
      return remoteToLocalPageIds[value] ?? value;
    }
    if (key == 'bookmarkedPageIds' && value is List<Object?>) {
      return [
        for (final pageId in value)
          if (pageId is String) remoteToLocalPageIds[pageId] ?? pageId,
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _rewritePageReferences(
            entry.value,
            remoteToLocalPageIds,
            key: entry.key as String,
          ),
      };
    }
    if (value is List<Object?>) {
      return [
        for (final item in value)
          _rewritePageReferences(item, remoteToLocalPageIds),
      ];
    }
    return value;
  }
}

sealed class _SharedSnapshot {
  const _SharedSnapshot({required this.revision, required this.contentHash});

  factory _SharedSnapshot.notebook(CloudSyncNotebook value) =
      _NotebookSharedSnapshot;
  factory _SharedSnapshot.folder(CloudSyncFolder value) = _FolderSharedSnapshot;
  factory _SharedSnapshot.page(CloudSyncPage value) = _PageSharedSnapshot;
  factory _SharedSnapshot.canvas(CloudSyncInfiniteCanvas value) =
      _CanvasSharedSnapshot;

  final int revision;
  final String contentHash;
}

class _FolderSharedSnapshot extends _SharedSnapshot {
  _FolderSharedSnapshot(this.value)
    : super(revision: value.revision, contentHash: value.contentHash);

  final CloudSyncFolder value;
}

class _NotebookSharedSnapshot extends _SharedSnapshot {
  _NotebookSharedSnapshot(this.value)
    : super(revision: value.revision, contentHash: value.contentHash);

  final CloudSyncNotebook value;
}

class _PageSharedSnapshot extends _SharedSnapshot {
  _PageSharedSnapshot(this.value)
    : super(revision: value.revision, contentHash: value.contentHash);

  final CloudSyncPage value;
}

class _CanvasSharedSnapshot extends _SharedSnapshot {
  _CanvasSharedSnapshot(this.value)
    : super(revision: value.revision, contentHash: value.contentHash);

  final CloudSyncInfiniteCanvas value;
}

class _SharedApplyAction {
  const _SharedApplyAction({required this.apply, required this.rollback});

  final Future<void> Function() apply;
  final Future<void> Function() rollback;
}

class _PageOrderPreparation {
  const _PageOrderPreparation({
    required this.actions,
    required this.expectedPagePositions,
    required this.expectedPageOrders,
  });

  final List<_SharedApplyAction> actions;
  final Map<String, int> expectedPagePositions;
  final Map<String, List<String>> expectedPageOrders;
}
