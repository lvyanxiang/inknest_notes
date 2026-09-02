import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/sync/sync_state.dart';

enum SyncStructuralConflictResolution { useLocal, useCloud }

class SyncStructuralConflict {
  SyncStructuralConflict({
    required this.resourceType,
    required this.resourceId,
    required this.cloudRevision,
    required List<String> fields,
    required Map<String, Object?> localMetadata,
    required Map<String, Object?> baseMetadata,
    required Map<String, Object?> cloudMetadata,
  }) : fields = List.unmodifiable(fields),
       localMetadata = Map.unmodifiable(localMetadata),
       baseMetadata = Map.unmodifiable(baseMetadata),
       cloudMetadata = Map.unmodifiable(cloudMetadata);

  final SyncResourceType resourceType;
  final String resourceId;
  final int cloudRevision;
  final List<String> fields;
  final Map<String, Object?> localMetadata;
  final Map<String, Object?> baseMetadata;
  final Map<String, Object?> cloudMetadata;

  String get id => '${resourceType.apiValue}:$resourceId';

  factory SyncStructuralConflict.fromJson(Map<String, Object?> json) {
    final fields = json['fields'];
    final cloudRevision = json['cloudRevision'];
    if (fields is! List<Object?> ||
        fields.any((field) => field is! String) ||
        cloudRevision is! int ||
        cloudRevision < 0) {
      throw const FormatException('Invalid structural conflict.');
    }
    Map<String, Object?> object(String key) =>
        (json[key]! as Map<Object?, Object?>).cast<String, Object?>();
    return SyncStructuralConflict(
      resourceType: SyncResourceType.fromApiValue(
        json['resourceType']! as String,
      ),
      resourceId: json['resourceId']! as String,
      cloudRevision: cloudRevision,
      fields: fields.cast<String>(),
      localMetadata: object('localMetadata'),
      baseMetadata: object('baseMetadata'),
      cloudMetadata: object('cloudMetadata'),
    );
  }

  Map<String, Object?> toJson() => {
    'resourceType': resourceType.apiValue,
    'resourceId': resourceId,
    'cloudRevision': cloudRevision,
    'fields': fields,
    'localMetadata': localMetadata,
    'baseMetadata': baseMetadata,
    'cloudMetadata': cloudMetadata,
  };
}

class FileSyncStructuralConflictStore {
  FileSyncStructuralConflictStore({
    required Directory rootDirectory,
    required String userId,
    required String deviceId,
  }) : _file = File(
         '${rootDirectory.path}/sync/$userId/$deviceId/structural_conflicts.json',
       );

  final File _file;
  Future<void> _queue = Future.value();
  int _temporaryCounter = 0;

  Future<List<SyncStructuralConflict>> load() async {
    await _queue.catchError((_) {});
    return _read();
  }

  Future<void> put(SyncStructuralConflict conflict) => _mutate((items) {
    items.removeWhere((item) => item.id == conflict.id);
    items.add(conflict);
    items.sort((left, right) => left.id.compareTo(right.id));
  });

  Future<void> remove(String id) =>
      _mutate((items) => items.removeWhere((item) => item.id == id));

  Future<void> _mutate(void Function(List<SyncStructuralConflict>) action) {
    final next = _queue.catchError((_) {}).then((_) async {
      final items = await _read();
      action(items);
      await _write(items);
    });
    _queue = next;
    return next;
  }

  Future<List<SyncStructuralConflict>> _read() async {
    if (!await _file.exists()) return [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['formatVersion'] != 1) {
      throw const FormatException('Invalid structural conflict store.');
    }
    return (decoded['conflicts']! as List<Object?>)
        .map(
          (item) => SyncStructuralConflict.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> _write(List<SyncStructuralConflict> items) async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp-${_temporaryCounter++}');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'conflicts': items.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }
}

class SyncStructuralConflictResolutionResult {
  const SyncStructuralConflictResolutionResult({
    required this.pendingConflicts,
  });

  final List<SyncStructuralConflict> pendingConflicts;
}

abstract interface class SyncStructuralConflictResolutionService {
  Future<List<SyncStructuralConflict>> loadStructuralConflicts({
    required String userId,
    required String deviceId,
  });

  Future<SyncStructuralConflictResolutionResult> resolveStructuralConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncStructuralConflictResolution resolution,
  });
}
