import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';

class SyncPageDeletionResult {
  const SyncPageDeletionResult({
    required this.deletedPageCount,
    required this.confirmedLocalPageDeletionCount,
  });

  final int deletedPageCount;
  final int confirmedLocalPageDeletionCount;
}

class SyncPageDeletionService {
  const SyncPageDeletionService({required this.rootDirectory});

  final Directory rootDirectory;

  Future<SyncPageDeletionResult?> applyIfSafe({
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
    final pageUpserts = changes
        .where(
          (change) =>
              change.resourceType == CloudSyncChangeResourceType.page &&
              change.operation == CloudSyncChangeOperation.upsert,
        )
        .toList();
    if (deletes.isEmpty ||
        deletes.length + tombstoneChanges.length + pageUpserts.length !=
            changes.length ||
        deletes.any(
          (change) =>
              change.resourceType != CloudSyncChangeResourceType.page ||
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
        tombstones.map((item) => item.resourceId).toSet().length !=
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
    final plans = <_PageDeletionPlan>[];
    final plannedNotebookIds = <String>{};

    for (final change in deletes) {
      final mapping = _mappingFor(mappings, change.resourceId);
      if (mapping == null) return null;
      final location = _locationFor(notebooks, mapping);
      final tombstone = _tombstoneFor(tombstones, change.resourceId);
      if (location == null ||
          tombstone == null ||
          !plannedNotebookIds.add(location.notebook.id) ||
          bootstrap.pages.any((page) => page.id == change.resourceId) ||
          tombstone.resourceType != 'page' ||
          tombstone.state != 'active' ||
          tombstone.deletedRevision != change.revision ||
          tombstone.contentHash != change.contentHash ||
          change.revision != mapping.revision + 1 ||
          change.contentHash != mapping.contentHash ||
          tombstone.resourceRevision != mapping.revision) {
        return null;
      }

      final pageIndex = location.notebook.pageIds.indexOf(location.pageId);
      final structurePosition = tombstone.structureMetadata['position'];
      final structureNotebookId = tombstone.structureMetadata['notebookId'];
      if (structurePosition is! int ||
          structurePosition < 0 ||
          structureNotebookId != location.notebook.id ||
          (pageIndex != -1 && structurePosition != pageIndex)) {
        return null;
      }
      final source = File(
        '${rootDirectory.path}/notebooks/${location.notebook.id}/pages/'
        '${location.pageId}.json',
      );
      final recovery = Directory(
        '${rootDirectory.path}/sync/$userId/$deviceId/deleted/${tombstone.id}',
      );
      final recoveryPage = File('${recovery.path}/page.json');
      final sourceExists = await source.exists();
      final recoveryExists = await recoveryPage.exists();
      final alreadyRecovered =
          pageIndex == -1 && !sourceExists && recoveryExists;
      final locallyDeleted =
          pageIndex == -1 &&
          !sourceExists &&
          !recoveryExists &&
          change.deviceId == deviceId;
      if (!alreadyRecovered &&
          !locallyDeleted &&
          (location.notebook.pageIds.length <= 1 || !sourceExists)) {
        return null;
      }
      if (!_matchesRemainingStructure(
        notebook: location.notebook,
        deletedPageId: location.pageId,
        locallyAbsent: alreadyRecovered || locallyDeleted,
        bootstrap: bootstrap,
        mappings: mappings,
      )) {
        return null;
      }
      plans.add(
        _PageDeletionPlan(
          notebook: location.notebook,
          pageId: location.pageId,
          tombstone: tombstone,
          source: source,
          recovery: recovery,
          alreadyRecovered: alreadyRecovered,
          locallyDeleted: locallyDeleted,
          originalPosition: structurePosition,
        ),
      );
    }
    if (plans.length != tombstones.length) return null;
    if (!_matchesStructuralUpserts(
      changes: pageUpserts,
      bootstrap: bootstrap,
      mappings: mappings,
    )) {
      return null;
    }

    final moved = <_PageDeletionPlan>[];
    try {
      for (final plan in plans) {
        if (plan.locallyDeleted) continue;
        if (!plan.alreadyRecovered) {
          await plan.recovery.create(recursive: true);
          await plan.source.rename('${plan.recovery.path}/page.json');
          moved.add(plan);
        }
        await File('${plan.recovery.path}/location.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'formatVersion': 1,
            'notebookId': plan.notebook.id,
            'pageId': plan.pageId,
            'position': plan.originalPosition,
          }),
          flush: true,
        );
        await File('${plan.recovery.path}/tombstone.json').writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'formatVersion': 1, 'tombstone': plan.tombstone.toJson()}),
          flush: true,
        );
      }
      final updatedById = {
        for (final plan in plans)
          if (!plan.locallyDeleted)
            plan.notebook.id: plan.notebook.copyWith(
              updatedAt: DateTime.now(),
              pageIds: [
                for (final pageId in plan.notebook.pageIds)
                  if (pageId != plan.pageId) pageId,
              ],
              bookmarkedPageIds: [
                for (final pageId in plan.notebook.bookmarkedPageIds)
                  if (pageId != plan.pageId) pageId,
              ],
            ),
      };
      await _replaceJson(indexFile, [
        for (final notebook in notebooks)
          (updatedById[notebook.id] ?? notebook).toJson(),
      ]);
    } on Object {
      await indexFile.writeAsBytes(previousIndexBytes, flush: true);
      for (final plan in moved.reversed) {
        final recoveryPage = File('${plan.recovery.path}/page.json');
        if (await recoveryPage.exists() && !await plan.source.exists()) {
          await recoveryPage.rename(plan.source.path);
        }
        if (await plan.recovery.exists()) {
          await plan.recovery.delete(recursive: true);
        }
      }
      rethrow;
    }

    return SyncPageDeletionResult(
      deletedPageCount: plans.where((plan) => !plan.locallyDeleted).length,
      confirmedLocalPageDeletionCount: plans
          .where((plan) => plan.locallyDeleted)
          .length,
    );
  }

  SyncResourceMapping? _mappingFor(
    List<SyncResourceMapping> mappings,
    String remotePageId,
  ) {
    for (final mapping in mappings) {
      if (mapping.resourceType == SyncResourceType.page &&
          mapping.remoteResourceId == remotePageId) {
        return mapping;
      }
    }
    return null;
  }

  _LocalPageLocation? _locationFor(
    List<Notebook> notebooks,
    SyncResourceMapping mapping,
  ) {
    final sorted = notebooks.toList()
      ..sort((left, right) => right.id.length.compareTo(left.id.length));
    for (final notebook in sorted) {
      final prefix = 'page:${notebook.id}:';
      if (!mapping.localKey.startsWith(prefix)) continue;
      final pageId = mapping.localKey.substring(prefix.length);
      if (pageId.isNotEmpty &&
          mapping.localKey == pageSyncLocalKey(notebook.id, pageId)) {
        return _LocalPageLocation(notebook: notebook, pageId: pageId);
      }
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

  bool _matchesRemainingStructure({
    required Notebook notebook,
    required String deletedPageId,
    required bool locallyAbsent,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
  }) {
    final remainingLocalIds = locallyAbsent
        ? notebook.pageIds
        : notebook.pageIds.where((pageId) => pageId != deletedPageId).toList();
    final cloudPages =
        bootstrap.pages.where((page) => page.notebookId == notebook.id).toList()
          ..sort((left, right) => left.position.compareTo(right.position));
    if (cloudPages.length != remainingLocalIds.length) return false;
    for (final (position, localPageId) in remainingLocalIds.indexed) {
      if (cloudPages[position].position != position) return false;
      SyncResourceMapping? mapping;
      for (final candidate in mappings) {
        if (candidate.localKey == pageSyncLocalKey(notebook.id, localPageId)) {
          mapping = candidate;
          break;
        }
      }
      if (mapping == null ||
          mapping.remoteResourceId != cloudPages[position].id) {
        return false;
      }
    }
    return true;
  }

  bool _matchesStructuralUpserts({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required List<SyncResourceMapping> mappings,
  }) {
    final changesById = {
      for (final change in changes) change.resourceId: change,
    };
    if (changesById.length != changes.length) return false;
    for (final page in bootstrap.pages) {
      SyncResourceMapping? mapping;
      for (final candidate in mappings) {
        if (candidate.resourceType == SyncResourceType.page &&
            candidate.remoteResourceId == page.id) {
          mapping = candidate;
          break;
        }
      }
      if (mapping == null) continue;
      final change = changesById.remove(page.id);
      if (page.revision == mapping.revision) {
        if (change != null) return false;
        continue;
      }
      if (change == null ||
          change.revision != mapping.revision + 1 ||
          change.contentHash != mapping.contentHash ||
          page.revision != change.revision ||
          page.contentHash != change.contentHash) {
        return false;
      }
    }
    return changesById.isEmpty;
  }

  Future<void> _replaceJson(File file, Object value) async {
    final temporary = File('${file.path}.sync-page-delete.tmp');
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

class _LocalPageLocation {
  const _LocalPageLocation({required this.notebook, required this.pageId});

  final Notebook notebook;
  final String pageId;
}

class _PageDeletionPlan {
  const _PageDeletionPlan({
    required this.notebook,
    required this.pageId,
    required this.tombstone,
    required this.source,
    required this.recovery,
    required this.alreadyRecovered,
    required this.locallyDeleted,
    required this.originalPosition,
  });

  final Notebook notebook;
  final String pageId;
  final CloudSyncTombstone tombstone;
  final File source;
  final Directory recovery;
  final bool alreadyRecovered;
  final bool locallyDeleted;
  final int originalPosition;
}
