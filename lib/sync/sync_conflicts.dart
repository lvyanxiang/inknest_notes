import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_changes.dart';

class CloudSyncConflict {
  CloudSyncConflict({
    required this.id,
    required this.resourceType,
    required this.originalResourceId,
    required this.copyResourceId,
    required this.copyDisplayName,
    required this.baseRevision,
    required this.currentRevision,
    required this.submittedContentHash,
    required Map<String, Object?> submittedContent,
    required this.currentContentHash,
    required Map<String, Object?> currentContent,
    required this.sourceDeviceId,
    required this.status,
    required this.resolution,
    required this.resolvedByDeviceId,
    required this.resolvedAt,
    required this.createdAt,
  }) : submittedContent = Map.unmodifiable(submittedContent),
       currentContent = Map.unmodifiable(currentContent);

  final String id;
  final String resourceType;
  final String originalResourceId;
  final String copyResourceId;
  final String copyDisplayName;
  final int baseRevision;
  final int currentRevision;
  final String submittedContentHash;
  final Map<String, Object?> submittedContent;
  final String currentContentHash;
  final Map<String, Object?> currentContent;
  final String? sourceDeviceId;
  final String status;
  final String? resolution;
  final String? resolvedByDeviceId;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory CloudSyncConflict.fromJson(Map<String, Object?> json) {
    final resourceType = requiredString(json, 'resourceType');
    final baseRevision = requiredNonNegativeInt(json, 'baseRevision');
    final currentRevision = requiredNonNegativeInt(json, 'currentRevision');
    final status = requiredString(json, 'status');
    final resolution = _optionalString(json, 'resolution');
    final resolvedAt = _optionalDateTime(json, 'resolvedAt');
    if (!const {'notebook', 'page'}.contains(resourceType) ||
        currentRevision < baseRevision ||
        !const {'pending', 'resolved'}.contains(status) ||
        (resolution != null &&
            !const {
              'keep_original',
              'use_conflict',
              'keep_both',
            }.contains(resolution)) ||
        (status == 'pending' && (resolution != null || resolvedAt != null)) ||
        (status == 'resolved' && (resolution == null || resolvedAt == null))) {
      throw const FormatException('Invalid synchronization conflict state.');
    }
    return CloudSyncConflict(
      id: requiredString(json, 'id'),
      resourceType: resourceType,
      originalResourceId: requiredString(json, 'conflictOf'),
      copyResourceId: requiredString(json, 'copyResourceId'),
      copyDisplayName: requiredString(json, 'copyDisplayName'),
      baseRevision: baseRevision,
      currentRevision: currentRevision,
      submittedContentHash: requiredSha256(json, 'submittedContentHash'),
      submittedContent: copyJsonObject(
        json['submittedContent'],
        'conflict.submittedContent',
      ),
      currentContentHash: requiredSha256(json, 'currentContentHash'),
      currentContent: copyJsonObject(
        json['currentContent'],
        'conflict.currentContent',
      ),
      sourceDeviceId: _optionalString(json, 'sourceDeviceId'),
      status: status,
      resolution: resolution,
      resolvedByDeviceId: _optionalString(json, 'resolvedByDeviceId'),
      resolvedAt: resolvedAt,
      createdAt: requiredDateTime(json, 'createdAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'resourceType': resourceType,
    'conflictOf': originalResourceId,
    'copyResourceId': copyResourceId,
    'copyDisplayName': copyDisplayName,
    'baseRevision': baseRevision,
    'currentRevision': currentRevision,
    'submittedContentHash': submittedContentHash,
    'submittedContent': submittedContent,
    'currentContentHash': currentContentHash,
    'currentContent': currentContent,
    if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
    'status': status,
    if (resolution != null) 'resolution': resolution,
    if (resolvedByDeviceId != null) 'resolvedByDeviceId': resolvedByDeviceId,
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class FileSyncConflictStore {
  FileSyncConflictStore({
    required Directory rootDirectory,
    required String userId,
    required String deviceId,
  }) : _file = File(
         '${rootDirectory.path}/sync/$userId/$deviceId/conflicts.json',
       );

  final File _file;
  Future<void> _writeQueue = Future.value();
  int _temporaryCounter = 0;

  Future<List<CloudSyncConflict>> loadPending() async {
    await _writeQueue.catchError((_) {});
    final all = await _read();
    return all.where((conflict) => conflict.isPending).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<CloudSyncConflict>> applyChanges(List<CloudSyncChange> changes) {
    final previous = _writeQueue;
    final next = previous.catchError((_) {}).then((_) async {
      final existing = {for (final item in await _read()) item.id: item};
      for (final change in changes) {
        if (change.resourceType != CloudSyncChangeResourceType.conflict ||
            change.operation != CloudSyncChangeOperation.upsert ||
            change.payload == null) {
          throw const FormatException(
            'Only conflict upsert changes can enter the conflict store.',
          );
        }
        final conflict = CloudSyncConflict.fromJson(change.payload!);
        if (conflict.id != change.resourceId) {
          throw const FormatException(
            'Conflict change resource ID does not match its payload.',
          );
        }
        existing[conflict.id] = conflict;
      }
      await _write(existing.values.toList());
      final pending =
          existing.values.where((conflict) => conflict.isPending).toList()
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return pending;
    });
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<List<CloudSyncConflict>> _read() async {
    if (!await _file.exists()) return [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['formatVersion'] != 1 ||
        decoded['conflicts'] is! List<Object?>) {
      throw const FormatException('Invalid synchronization conflict store.');
    }
    return (decoded['conflicts']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(CloudSyncConflict.fromJson)
        .toList();
  }

  Future<void> _write(List<CloudSyncConflict> conflicts) async {
    await _file.parent.create(recursive: true);
    conflicts.sort((left, right) => left.id.compareTo(right.id));
    final temporary = File('${_file.path}.tmp-${_temporaryCounter++}');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
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
