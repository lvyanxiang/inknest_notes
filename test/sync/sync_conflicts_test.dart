import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

void main() {
  test(
    'persists pending conflicts and removes resolved items from the list',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-conflicts-');
      addTearDown(() => root.delete(recursive: true));
      final store = FileSyncConflictStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      final pending = await store.applyChanges([_change(_conflictPayload())]);
      final reloaded = await FileSyncConflictStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).loadPending();

      expect(pending.single.copyDisplayName, '第 2 页（冲突副本）');
      expect(reloaded.single.id, 'conflict-1');

      final resolved = await store.applyChanges([
        _change(
          _conflictPayload(
            status: 'resolved',
            resolution: 'keep_both',
            resolvedAt: '2026-08-07T01:00:00Z',
          ),
        ),
      ]);

      expect(resolved, isEmpty);
      expect(await store.loadPending(), isEmpty);
    },
  );
}

CloudSyncChange _change(Map<String, Object?> payload) => CloudSyncChange(
  changeId: 'change-conflict-1',
  resourceType: CloudSyncChangeResourceType.conflict,
  resourceId: 'conflict-1',
  operation: CloudSyncChangeOperation.upsert,
  revision: null,
  contentHash: null,
  payload: payload,
  deviceId: 'device-2',
  createdAt: DateTime.utc(2026, 8, 7),
);

Map<String, Object?> _conflictPayload({
  String status = 'pending',
  String? resolution,
  String? resolvedAt,
}) {
  final payload = <String, Object?>{
    'id': 'conflict-1',
    'resourceType': 'page',
    'conflictOf': 'page-2',
    'copyResourceId': 'page-conflict-copy',
    'copyDisplayName': '第 2 页（冲突副本）',
    'baseRevision': 1,
    'currentRevision': 2,
    'submittedContentHash': 'a' * 64,
    'submittedContent': const {'strokes': <Object?>[]},
    'currentContentHash': 'b' * 64,
    'currentContent': const {'strokes': <Object?>[]},
    'sourceDeviceId': 'device-2',
    'status': status,
    'createdAt': '2026-08-07T00:00:00Z',
  };
  if (resolution != null) {
    payload['resolution'] = resolution;
    payload['resolvedByDeviceId'] = 'device-1';
  }
  if (resolvedAt != null) payload['resolvedAt'] = resolvedAt;
  return payload;
}
