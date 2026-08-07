import 'package:inknest_notes/sync/inknest_api_models.dart';

enum CloudSyncChangeResourceType {
  folder('folder'),
  notebook('notebook'),
  page('page'),
  infiniteCanvas('infinite_canvas'),
  asset('asset'),
  conflict('conflict'),
  tombstone('tombstone');

  const CloudSyncChangeResourceType(this.apiValue);

  final String apiValue;

  static CloudSyncChangeResourceType fromApiValue(String value) {
    return values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException(
        'Unsupported synchronization change resource type: $value',
      ),
    );
  }
}

enum CloudSyncChangeOperation {
  upsert('upsert'),
  delete('delete');

  const CloudSyncChangeOperation(this.apiValue);

  final String apiValue;

  static CloudSyncChangeOperation fromApiValue(String value) {
    return values.firstWhere(
      (operation) => operation.apiValue == value,
      orElse: () => throw FormatException(
        'Unsupported synchronization change operation: $value',
      ),
    );
  }
}

class CloudSyncChange {
  CloudSyncChange({
    required this.changeId,
    required this.resourceType,
    required this.resourceId,
    required this.operation,
    required this.revision,
    required this.contentHash,
    required Map<String, Object?>? payload,
    required this.deviceId,
    required this.createdAt,
  }) : payload = payload == null ? null : Map.unmodifiable(payload);

  final String changeId;
  final CloudSyncChangeResourceType resourceType;
  final String resourceId;
  final CloudSyncChangeOperation operation;
  final int? revision;
  final String? contentHash;
  final Map<String, Object?>? payload;
  final String? deviceId;
  final DateTime createdAt;

  factory CloudSyncChange.fromJson(Map<String, Object?> json) {
    final revision = json['revision'];
    if (revision != null && (revision is! int || revision < 0)) {
      throw const FormatException(
        'Synchronization change revision must be non-negative or null.',
      );
    }
    final contentHash = json['contentHash'];
    if (contentHash != null &&
        (contentHash is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash))) {
      throw const FormatException(
        'Synchronization change contentHash must be SHA-256 or null.',
      );
    }
    final rawPayload = json['payload'];
    if (rawPayload != null && rawPayload is! Map<Object?, Object?>) {
      throw const FormatException(
        'Synchronization change payload must be an object or null.',
      );
    }
    final deviceId = json['deviceId'];
    if (deviceId != null &&
        (deviceId is! String ||
            deviceId.isEmpty ||
            deviceId.trim() != deviceId)) {
      throw const FormatException(
        'Synchronization change deviceId must be a string or null.',
      );
    }
    return CloudSyncChange(
      changeId: requiredString(json, 'changeId'),
      resourceType: CloudSyncChangeResourceType.fromApiValue(
        requiredString(json, 'resourceType'),
      ),
      resourceId: requiredString(json, 'resourceId'),
      operation: CloudSyncChangeOperation.fromApiValue(
        requiredString(json, 'operation'),
      ),
      revision: revision as int?,
      contentHash: contentHash as String?,
      payload: rawPayload == null
          ? null
          : copyJsonObject(rawPayload, 'syncChange.payload'),
      deviceId: deviceId as String?,
      createdAt: requiredDateTime(json, 'createdAt'),
    );
  }
}

class CloudSyncChangePage {
  CloudSyncChangePage({
    required List<CloudSyncChange> changes,
    required this.nextCursor,
    required this.hasMore,
  }) : changes = List.unmodifiable(changes);

  final List<CloudSyncChange> changes;
  final String nextCursor;
  final bool hasMore;

  factory CloudSyncChangePage.fromJson(Map<String, Object?> json) {
    final rawChanges = json['changes'];
    final nextCursor = json['nextCursor'];
    final hasMore = json['hasMore'];
    if (rawChanges is! List<Object?> ||
        rawChanges.any((item) => item is! Map<Object?, Object?>) ||
        nextCursor is! String ||
        nextCursor.isEmpty ||
        nextCursor.trim() != nextCursor ||
        hasMore is! bool) {
      throw const FormatException('Invalid synchronization change page.');
    }
    final changes = rawChanges
        .map(
          (item) => CloudSyncChange.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
    if (changes.map((item) => item.changeId).toSet().length != changes.length ||
        (hasMore && changes.isEmpty)) {
      throw const FormatException(
        'Synchronization change page has invalid pagination data.',
      );
    }
    return CloudSyncChangePage(
      changes: changes,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }
}
