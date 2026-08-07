import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';

void main() {
  test('persists active Tombstones and hides restored records', () async {
    final root = await Directory.systemTemp.createTemp('inknest-tombstones-');
    addTearDown(() => root.delete(recursive: true));
    final store = FileSyncTombstoneStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    final active = await store.applyChanges([_change(_payload())]);
    final reloaded = await FileSyncTombstoneStore(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
    ).loadActive();

    expect(active.single.resourceLabel, '已删除的笔记');
    expect(reloaded.single.id, 'tombstone-1');

    final restored = await store.applyChanges([
      _change(_payload(restored: true)),
    ]);

    expect(restored, isEmpty);
    expect(await store.loadActive(), isEmpty);
  });
}

CloudSyncChange _change(Map<String, Object?> payload) => CloudSyncChange(
  changeId: 'change-${payload['state']}',
  resourceType: CloudSyncChangeResourceType.tombstone,
  resourceId: 'tombstone-1',
  operation: CloudSyncChangeOperation.upsert,
  revision: null,
  contentHash: null,
  payload: payload,
  deviceId: 'device-1',
  createdAt: DateTime.utc(2026, 8, 7),
);

Map<String, Object?> _payload({bool restored = false}) => {
  'id': 'tombstone-1',
  'resourceType': 'notebook',
  'resourceId': 'notebook-1',
  'baseRevision': 1,
  'resourceRevision': 1,
  'deletedRevision': 2,
  'contentHash': 'a' * 64,
  'content': const {'bookmarkedPageIds': <Object?>[]},
  'deletedByDeviceId': 'device-1',
  'deletedAt': '2026-08-07T00:00:00Z',
  'state': restored ? 'restored' : 'active',
  if (restored) 'resolution': 'restored_snapshot',
  if (restored) 'restoredByDeviceId': 'device-1',
  if (restored) 'restoredAt': '2026-08-07T01:00:00Z',
  'createdAt': '2026-08-07T00:00:00Z',
};
