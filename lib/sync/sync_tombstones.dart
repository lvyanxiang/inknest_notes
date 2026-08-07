import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_changes.dart';

class CloudSyncTombstone {
  CloudSyncTombstone({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    required this.baseRevision,
    required this.resourceRevision,
    required this.deletedRevision,
    required this.contentHash,
    required Map<String, Object?> content,
    required Map<String, Object?> structureMetadata,
    required this.deletedByDeviceId,
    required this.deletedAt,
    required this.state,
    required this.conflictKind,
    required this.resolution,
    required this.conflictingDeviceId,
    required this.restoredByDeviceId,
    required this.restoredAt,
    required this.createdAt,
  }) : content = Map.unmodifiable(content),
       structureMetadata = Map.unmodifiable(structureMetadata);

  final String id;
  final String resourceType;
  final String resourceId;
  final int baseRevision;
  final int resourceRevision;
  final int? deletedRevision;
  final String contentHash;
  final Map<String, Object?> content;
  final Map<String, Object?> structureMetadata;
  final String? deletedByDeviceId;
  final DateTime deletedAt;
  final String state;
  final String? conflictKind;
  final String? resolution;
  final String? conflictingDeviceId;
  final String? restoredByDeviceId;
  final DateTime? restoredAt;
  final DateTime createdAt;

  bool get isActive => state == 'active';

  bool get isRestorableInApp =>
      isActive && const {'notebook', 'page'}.contains(resourceType);

  String get resourceLabel => switch (resourceType) {
    'notebook' => '已删除的笔记',
    'page' => '已删除的页面',
    _ => '已删除的无限画布',
  };

  factory CloudSyncTombstone.fromJson(Map<String, Object?> json) {
    final resourceType = requiredString(json, 'resourceType');
    final baseRevision = requiredNonNegativeInt(json, 'baseRevision');
    final resourceRevision = requiredNonNegativeInt(json, 'resourceRevision');
    final deletedRevision = json['deletedRevision'];
    final state = requiredString(json, 'state');
    final conflictKind = _optionalString(json, 'conflictKind');
    final resolution = _optionalString(json, 'resolution');
    final restoredAt = _optionalDateTime(json, 'restoredAt');
    if (!const {'notebook', 'page', 'infinite_canvas'}.contains(resourceType) ||
        (deletedRevision != null &&
            (deletedRevision is! int || deletedRevision < 0)) ||
        !const {'active', 'restored'}.contains(state) ||
        (conflictKind != null &&
            !const {
              'delete_after_edit',
              'edit_after_delete',
            }.contains(conflictKind)) ||
        (resolution != null &&
            !const {
              'restored_snapshot',
              'preserved_edit',
            }.contains(resolution)) ||
        (state == 'active' && (resolution != null || restoredAt != null)) ||
        (state == 'restored' && (resolution == null || restoredAt == null))) {
      throw const FormatException('Invalid synchronization Tombstone.');
    }
    return CloudSyncTombstone(
      id: requiredString(json, 'id'),
      resourceType: resourceType,
      resourceId: requiredString(json, 'resourceId'),
      baseRevision: baseRevision,
      resourceRevision: resourceRevision,
      deletedRevision: deletedRevision as int?,
      contentHash: requiredSha256(json, 'contentHash'),
      content: copyJsonObject(json['content'], 'tombstone.content'),
      structureMetadata: json['structureMetadata'] == null
          ? const {}
          : copyJsonObject(
              json['structureMetadata'],
              'tombstone.structureMetadata',
            ),
      deletedByDeviceId: _optionalString(json, 'deletedByDeviceId'),
      deletedAt: requiredDateTime(json, 'deletedAt'),
      state: state,
      conflictKind: conflictKind,
      resolution: resolution,
      conflictingDeviceId: _optionalString(json, 'conflictingDeviceId'),
      restoredByDeviceId: _optionalString(json, 'restoredByDeviceId'),
      restoredAt: restoredAt,
      createdAt: requiredDateTime(json, 'createdAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'baseRevision': baseRevision,
    'resourceRevision': resourceRevision,
    'deletedRevision': deletedRevision,
    'contentHash': contentHash,
    'content': content,
    'structureMetadata': structureMetadata,
    if (deletedByDeviceId != null) 'deletedByDeviceId': deletedByDeviceId,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
    'state': state,
    if (conflictKind != null) 'conflictKind': conflictKind,
    if (resolution != null) 'resolution': resolution,
    if (conflictingDeviceId != null) 'conflictingDeviceId': conflictingDeviceId,
    if (restoredByDeviceId != null) 'restoredByDeviceId': restoredByDeviceId,
    if (restoredAt != null) 'restoredAt': restoredAt!.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class FileSyncTombstoneStore {
  FileSyncTombstoneStore({
    required Directory rootDirectory,
    required String userId,
    required String deviceId,
  }) : _file = File(
         '${rootDirectory.path}/sync/$userId/$deviceId/tombstones.json',
       );

  final File _file;
  Future<void> _writeQueue = Future.value();
  int _temporaryCounter = 0;

  Future<List<CloudSyncTombstone>> loadActive() async {
    await _writeQueue.catchError((_) {});
    return _active(await _read());
  }

  Future<List<CloudSyncTombstone>> applyChanges(List<CloudSyncChange> changes) {
    final previous = _writeQueue;
    final next = previous.catchError((_) {}).then((_) async {
      final existing = {for (final item in await _read()) item.id: item};
      for (final change in changes) {
        if (change.resourceType != CloudSyncChangeResourceType.tombstone ||
            change.operation != CloudSyncChangeOperation.upsert ||
            change.payload == null) {
          throw const FormatException(
            'Only Tombstone upsert changes can enter the Tombstone store.',
          );
        }
        final tombstone = CloudSyncTombstone.fromJson(change.payload!);
        if (tombstone.id != change.resourceId) {
          throw const FormatException(
            'Tombstone change resource ID does not match its payload.',
          );
        }
        existing[tombstone.id] = tombstone;
      }
      await _write(existing.values.toList());
      return _active(existing.values);
    });
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  List<CloudSyncTombstone> _active(Iterable<CloudSyncTombstone> values) =>
      values.where((item) => item.isRestorableInApp).toList()
        ..sort((left, right) => right.deletedAt.compareTo(left.deletedAt));

  Future<List<CloudSyncTombstone>> _read() async {
    if (!await _file.exists()) return [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['formatVersion'] != 1 ||
        decoded['tombstones'] is! List<Object?>) {
      throw const FormatException('Invalid synchronization Tombstone store.');
    }
    return (decoded['tombstones']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(CloudSyncTombstone.fromJson)
        .toList();
  }

  Future<void> _write(List<CloudSyncTombstone> tombstones) async {
    await _file.parent.create(recursive: true);
    tombstones.sort((left, right) => left.id.compareTo(right.id));
    final temporary = File('${_file.path}.tmp-${_temporaryCounter++}');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'tombstones': tombstones.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
    try {
      await temporary.rename(_file.path);
    } on FileSystemException {
      if (await _file.exists()) await _file.delete();
      await temporary.rename(_file.path);
    }
  }
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw FormatException('$key must be a non-empty string or null.');
  }
  return value;
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a date or null.');
  return DateTime.parse(value).toUtc();
}
