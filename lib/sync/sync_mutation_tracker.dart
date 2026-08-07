import 'dart:io';

import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

typedef ActiveSyncSession = InkNestAuthSession? Function();

class SyncMutationTracker {
  SyncMutationTracker({
    required this.rootDirectory,
    required this.activeSession,
  });

  final Directory rootDirectory;
  final ActiveSyncSession activeSession;
  Future<void> _queue = Future.value();
  int _suppressionDepth = 0;

  Future<T> runWithoutTracking<T>(Future<T> Function() action) async {
    _suppressionDepth++;
    try {
      return await action();
    } finally {
      _suppressionDepth--;
    }
  }

  Future<void> pageSaved(Notebook notebook, NotePage page) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackPageSaved(notebook, page));
  }

  Future<void> notebookContentSaved(Notebook notebook) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackNotebookContent(notebook));
  }

  Future<void> notebookMetadataSaved(Notebook notebook) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackNotebookMetadata(notebook));
  }

  Future<void> folderSaved(NotebookFolder folder) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackFolder(folder));
  }

  Future<void> folderDeleted(NotebookFolder folder) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackFolderDeleted(folder));
  }

  Future<void> infiniteCanvasSaved(
    Notebook notebook,
    InfiniteCanvasDocument document,
  ) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackInfiniteCanvas(notebook, document));
  }

  Future<void> notebookDeleted(Notebook notebook) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackNotebookDeleted(notebook));
  }

  Future<void> pageDeleted(Notebook notebook, String pageId) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackPageDeleted(notebook, pageId));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.catchError((_) {}).then((_) => action());
    _queue = next;
    return next;
  }

  Future<void> _trackPageSaved(Notebook notebook, NotePage page) async {
    final session = activeSession();
    if (session == null) return;
    final mapping = await FileSyncResourceMapStore(
      rootDirectory: rootDirectory,
      userId: session.user.id,
      deviceId: session.device.id,
    ).find(pageSyncLocalKey(notebook.id, page.id));
    if (mapping == null) return;

    final content = Map<String, Object?>.from(page.toJson());
    for (final key in const {
      'id',
      'width',
      'height',
      'coordinateSpaceVersion',
      'rotationQuarterTurns',
      'template',
    }) {
      content.remove(key);
    }
    await FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: session.user.id,
      deviceId: session.device.id,
    ).enqueueUpsert(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
      content: content,
    );
  }

  Future<void> _trackNotebookContent(Notebook notebook) async {
    final session = activeSession();
    if (session == null) return;
    final resourceMap = _resourceMap(session);
    final resources = await resourceMap.load();
    final mapping = _findMapping(resources, notebookSyncLocalKey(notebook.id));
    if (mapping == null) return;
    final remotePageIds = <String, String>{};
    for (final pageId in notebook.pageIds) {
      final pageMapping = _findMapping(
        resources,
        pageSyncLocalKey(notebook.id, pageId),
      );
      if (pageMapping != null) {
        remotePageIds[pageId] = pageMapping.remoteResourceId;
      }
    }
    if (_referencedPageIds(
      notebook,
    ).any((pageId) => !remotePageIds.containsKey(pageId))) {
      return;
    }
    for (final recording in notebook.audioRecordings) {
      if (!await resourceMap.hasCloudAsset(notebook.id, recording.assetPath)) {
        return;
      }
    }

    final content = Map<String, Object?>.from(
      _rewritePageReferences(notebook.toJson(), remotePageIds)! as Map,
    );
    for (final key in const {
      'id',
      'title',
      'createdAt',
      'updatedAt',
      'pageIds',
      'isArchived',
      'folderId',
      'layoutMode',
    }) {
      content.remove(key);
    }
    await _stateStore(session).enqueueUpsert(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
      content: content,
    );
  }

  Future<void> _trackNotebookMetadata(Notebook notebook) async {
    final session = activeSession();
    if (session == null) return;
    final mapping = await _resourceMap(
      session,
    ).find(notebookSyncLocalKey(notebook.id));
    final baseMetadata = mapping?.notebookMetadata;
    if (mapping == null ||
        mapping.resourceType != SyncResourceType.notebook ||
        baseMetadata == null) {
      return;
    }
    await _stateStore(session).enqueueNotebookMetadata(
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
      baseMetadata: baseMetadata,
      metadata: {
        'title': notebook.title,
        'isArchived': notebook.isArchived,
        'folderId': notebook.folderId,
      },
    );
  }

  Future<void> _trackFolder(NotebookFolder folder) async {
    final session = activeSession();
    if (session == null) return;
    final stateStore = _stateStore(session);
    if ((await stateStore.loadSnapshot()).lastAppliedCursor == null) return;
    final mapping = await _resourceMap(
      session,
    ).find(folderSyncLocalKey(folder.id));
    if (mapping != null &&
        (mapping.resourceType != SyncResourceType.folder ||
            mapping.folderMetadata == null)) {
      return;
    }
    await stateStore.enqueueFolderMetadata(
      resourceId: mapping?.remoteResourceId ?? folder.id,
      baseRevision: mapping?.revision ?? 0,
      baseMetadata: mapping?.folderMetadata,
      metadata: {'name': folder.name},
    );
  }

  Future<void> _trackInfiniteCanvas(
    Notebook notebook,
    InfiniteCanvasDocument document,
  ) async {
    final session = activeSession();
    if (session == null) return;
    final resourceMap = _resourceMap(session);
    final mapping = await resourceMap.find(canvasSyncLocalKey(notebook.id));
    if (mapping == null) return;
    for (final image in document.images) {
      if (!await resourceMap.hasCloudAsset(notebook.id, image.assetPath)) {
        return;
      }
    }
    final content = Map<String, Object?>.from(document.toJson())
      ..remove('background');
    await _stateStore(session).enqueueUpsert(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
      content: content,
    );
  }

  Future<void> _trackNotebookDeleted(Notebook notebook) async {
    final session = activeSession();
    if (session == null) return;
    final mapping = await _resourceMap(
      session,
    ).find(notebookSyncLocalKey(notebook.id));
    if (mapping == null || mapping.resourceType != SyncResourceType.notebook) {
      return;
    }
    await _stateStore(session).enqueueDelete(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
    );
  }

  Future<void> _trackFolderDeleted(NotebookFolder folder) async {
    final session = activeSession();
    if (session == null) return;
    final stateStore = _stateStore(session);
    final mapping = await _resourceMap(
      session,
    ).find(folderSyncLocalKey(folder.id));
    if (mapping != null) {
      if (mapping.resourceType != SyncResourceType.folder) return;
      await stateStore.enqueueDelete(
        resourceType: SyncResourceType.folder,
        resourceId: mapping.remoteResourceId,
        baseRevision: mapping.revision,
      );
      return;
    }

    if (await stateStore.cancelPendingFolderCreation(folder.id)) return;
    final inFlightCreation = (await stateStore.loadSnapshot())
        .inFlightBatch
        ?.operations
        .any(
          (operation) =>
              operation.resourceType == SyncResourceType.folder &&
              operation.resourceId == folder.id &&
              operation.operation == SyncOperationKind.upsert &&
              operation.baseRevision == 0,
        );
    if (inFlightCreation ?? false) {
      await stateStore.enqueueDelete(
        resourceType: SyncResourceType.folder,
        resourceId: folder.id,
        baseRevision: 0,
      );
    }
  }

  Future<void> _trackPageDeleted(Notebook notebook, String pageId) async {
    if (notebook.pageIds.length <= 1 || !notebook.pageIds.contains(pageId)) {
      return;
    }
    final session = activeSession();
    if (session == null) return;
    final mapping = await _resourceMap(
      session,
    ).find(pageSyncLocalKey(notebook.id, pageId));
    if (mapping == null || mapping.resourceType != SyncResourceType.page) {
      return;
    }
    await _stateStore(session).enqueueDelete(
      resourceType: mapping.resourceType,
      resourceId: mapping.remoteResourceId,
      baseRevision: mapping.revision,
    );
  }

  FileSyncResourceMapStore _resourceMap(InkNestAuthSession session) =>
      FileSyncResourceMapStore(
        rootDirectory: rootDirectory,
        userId: session.user.id,
        deviceId: session.device.id,
      );

  FileSyncStateStore _stateStore(InkNestAuthSession session) =>
      FileSyncStateStore(
        rootDirectory: rootDirectory,
        userId: session.user.id,
        deviceId: session.device.id,
      );

  SyncResourceMapping? _findMapping(
    List<SyncResourceMapping> mappings,
    String localKey,
  ) {
    for (final mapping in mappings) {
      if (mapping.localKey == localKey) return mapping;
    }
    return null;
  }

  Set<String> _referencedPageIds(Notebook notebook) {
    final result = <String>{...notebook.bookmarkedPageIds};
    void addOutlines(Iterable<PdfOutlineEntry> outlines) {
      for (final outline in outlines) {
        if (outline.pageId case final String pageId) result.add(pageId);
        addOutlines(outline.children);
      }
    }

    addOutlines(notebook.pdfOutlines);
    for (final recording in notebook.audioRecordings) {
      if (recording.pageId case final String pageId) result.add(pageId);
    }
    return result;
  }

  Object? _rewritePageReferences(
    Object? value,
    Map<String, String> remotePageIds, {
    String? key,
  }) {
    if (key == 'pageId' && value is String) {
      return remotePageIds[value] ?? value;
    }
    if (key == 'bookmarkedPageIds' && value is List<Object?>) {
      return [
        for (final pageId in value)
          if (pageId is String) remotePageIds[pageId] ?? pageId,
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _rewritePageReferences(
            entry.value,
            remotePageIds,
            key: entry.key as String,
          ),
      };
    }
    if (value is List<Object?>) {
      return [
        for (final item in value) _rewritePageReferences(item, remotePageIds),
      ];
    }
    return value;
  }
}
