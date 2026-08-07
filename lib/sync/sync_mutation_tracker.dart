import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';
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

  Future<void> pageSaved(Notebook notebook, NotePage page) {
    final next = _queue
        .catchError((_) {})
        .then((_) => _trackPageSaved(notebook, page));
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
}
