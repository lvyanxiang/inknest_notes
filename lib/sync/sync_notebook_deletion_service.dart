import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';

class SyncNotebookDeletionResult {
  const SyncNotebookDeletionResult({required this.deletedNotebookCount});

  final int deletedNotebookCount;
}

class SyncNotebookDeletionService {
  const SyncNotebookDeletionService({required this.rootDirectory});

  final Directory rootDirectory;

  Future<SyncNotebookDeletionResult?> applyIfSafe({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
    required String userId,
    required String deviceId,
  }) async {
    final deletes = changes
        .where((change) => change.operation == CloudSyncChangeOperation.delete)
        .toList();
    final tombstoneChanges = changes
        .where(
          (change) =>
              change.resourceType == CloudSyncChangeResourceType.tombstone &&
              change.operation == CloudSyncChangeOperation.upsert,
        )
        .toList();
    if (deletes.isEmpty ||
        deletes.length + tombstoneChanges.length != changes.length ||
        deletes.any(
          (change) =>
              change.resourceType != CloudSyncChangeResourceType.notebook ||
              change.revision == null ||
              change.contentHash == null,
        )) {
      return null;
    }

    final tombstones = <CloudSyncTombstone>[];
    try {
      for (final change in tombstoneChanges) {
        final payload = change.payload;
        if (payload == null) return null;
        final tombstone = CloudSyncTombstone.fromJson(payload);
        if (tombstone.id != change.resourceId) return null;
        tombstones.add(tombstone);
      }
    } on FormatException {
      return null;
    }
    if (deletes.map((change) => change.resourceId).toSet().length !=
            deletes.length ||
        tombstones.map((tombstone) => tombstone.resourceId).toSet().length !=
            tombstones.length) {
      return null;
    }

    final indexFile = File('${rootDirectory.path}/notebooks/index.json');
    if (!await indexFile.exists()) return null;
    final previousIndexBytes = await indexFile.readAsBytes();
    final decoded = jsonDecode(utf8.decode(previousIndexBytes));
    if (decoded is! List<Object?>) return null;
    final notebooks = decoded
        .cast<Map<String, Object?>>()
        .map(Notebook.fromJson)
        .toList();
    final plans = <_NotebookDeletionPlan>[];
    for (final change in deletes) {
      final mapping = _mappingFor(mappings, change.resourceId);
      final tombstone = _tombstoneFor(tombstones, change.resourceId);
      if (tombstone == null ||
          bootstrap.inventory.notebookIds.contains(change.resourceId) ||
          tombstone.resourceType != 'notebook' ||
          tombstone.state != 'active' ||
          tombstone.deletedRevision != change.revision ||
          tombstone.contentHash != change.contentHash) {
        return null;
      }
      final source = Directory(
        '${rootDirectory.path}/notebooks/${change.resourceId}',
      );
      final recovery = Directory(
        '${rootDirectory.path}/sync/$userId/$deviceId/deleted/'
        '${tombstone.id}/notebook',
      );
      final recoveryExists = await recovery.exists();
      final sourceExists = await source.exists();
      final alreadyRecovered = recoveryExists && !sourceExists;
      var notebook = _notebookFor(notebooks, change.resourceId);
      if (notebook == null && alreadyRecovered) {
        final metadata = File('${recovery.parent.path}/local-notebook.json');
        if (await metadata.exists()) {
          final value = jsonDecode(await metadata.readAsString());
          if (value is Map<String, Object?>) {
            notebook = Notebook.fromJson(value);
          }
        }
      }
      final baselineRevision = mapping?.revision ?? tombstone.resourceRevision;
      final baselineHash = mapping?.contentHash ?? tombstone.contentHash;
      if (notebook == null ||
          (!alreadyRecovered && mapping == null) ||
          change.revision != baselineRevision + 1 ||
          change.contentHash != baselineHash ||
          tombstone.resourceRevision != baselineRevision) {
        return null;
      }
      plans.add(
        _NotebookDeletionPlan(
          notebook: notebook,
          tombstone: tombstone,
          source: source,
          recovery: recovery,
          alreadyRecovered: alreadyRecovered,
        ),
      );
    }
    if (plans.length != tombstones.length) return null;

    final moved = <_NotebookDeletionPlan>[];
    try {
      for (final plan in plans) {
        if (!plan.alreadyRecovered) {
          if (!await plan.source.exists() || await plan.recovery.exists()) {
            throw StateError(
              'Notebook deletion recovery path is inconsistent.',
            );
          }
          await plan.recovery.parent.create(recursive: true);
          await plan.source.rename(plan.recovery.path);
          moved.add(plan);
        }
        await File(
          '${plan.recovery.parent.path}/local-notebook.json',
        ).writeAsString(
          const JsonEncoder.withIndent('  ').convert(plan.notebook.toJson()),
          flush: true,
        );
        await File('${plan.recovery.parent.path}/tombstone.json').writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'formatVersion': 1, 'tombstone': plan.tombstone.toJson()}),
          flush: true,
        );
      }
      final deletedIds = plans.map((plan) => plan.notebook.id).toSet();
      await _replaceJson(indexFile, [
        for (final notebook in notebooks)
          if (!deletedIds.contains(notebook.id)) notebook.toJson(),
      ]);
    } on Object {
      await indexFile.writeAsBytes(previousIndexBytes, flush: true);
      for (final plan in moved.reversed) {
        if (await plan.recovery.exists() && !await plan.source.exists()) {
          await plan.recovery.rename(plan.source.path);
        }
      }
      rethrow;
    }
    return SyncNotebookDeletionResult(deletedNotebookCount: plans.length);
  }

  SyncResourceMapping? _mappingFor(
    List<SyncResourceMapping> mappings,
    String notebookId,
  ) {
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.notebook &&
          mapping.remoteResourceId == notebookId &&
          mapping.localKey == notebookSyncLocalKey(notebookId)) {
        return mapping;
      }
    }
    return null;
  }

  Notebook? _notebookFor(List<Notebook> notebooks, String id) {
    for (final notebook in notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  CloudSyncTombstone? _tombstoneFor(
    List<CloudSyncTombstone> tombstones,
    String resourceId,
  ) {
    for (final tombstone in tombstones) {
      if (tombstone.resourceId == resourceId) return tombstone;
    }
    return null;
  }

  Future<void> _replaceJson(File file, Object value) async {
    final temporary = File('${file.path}.sync-delete.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}

class _NotebookDeletionPlan {
  const _NotebookDeletionPlan({
    required this.notebook,
    required this.tombstone,
    required this.source,
    required this.recovery,
    required this.alreadyRecovered,
  });

  final Notebook notebook;
  final CloudSyncTombstone tombstone;
  final Directory source;
  final Directory recovery;
  final bool alreadyRecovered;
}
