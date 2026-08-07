import 'package:inknest_notes/sync/inknest_api_models.dart';

class CloudSyncTombstone {
  const CloudSyncTombstone({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    required this.baseRevision,
    required this.resourceRevision,
    required this.deletedRevision,
    required this.contentHash,
    required this.content,
    required this.state,
    required this.deletedAt,
  });

  final String id;
  final String resourceType;
  final String resourceId;
  final int baseRevision;
  final int resourceRevision;
  final int? deletedRevision;
  final String contentHash;
  final Map<String, Object?> content;
  final String state;
  final DateTime deletedAt;

  factory CloudSyncTombstone.fromJson(Map<String, Object?> json) {
    final resourceType = requiredString(json, 'resourceType');
    final baseRevision = json['baseRevision'];
    final resourceRevision = json['resourceRevision'];
    final deletedRevision = json['deletedRevision'];
    final state = requiredString(json, 'state');
    if (!const {'notebook', 'page', 'infinite_canvas'}.contains(resourceType) ||
        baseRevision is! int ||
        baseRevision < 0 ||
        resourceRevision is! int ||
        resourceRevision < 0 ||
        (deletedRevision != null &&
            (deletedRevision is! int || deletedRevision < 0)) ||
        !const {'active', 'restored'}.contains(state)) {
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
      state: state,
      deletedAt: requiredDateTime(json, 'deletedAt'),
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
    'state': state,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
  };
}
