import 'dart:io';

import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';

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

  Future<void> infiniteCanvasSaved(
    Notebook notebook,
    InfiniteCanvasDocument document,
  ) {
    if (_suppressionDepth > 0) return Future.value();
    return _enqueue(() => _trackInfiniteCanvas(notebook, document));
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
