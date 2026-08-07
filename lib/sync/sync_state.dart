enum SyncResourceType {
  notebook('notebook'),
  page('page'),
  infiniteCanvas('infinite_canvas');

  const SyncResourceType(this.apiValue);

  final String apiValue;

  static SyncResourceType fromApiValue(String value) {
    return values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException(
        'Unsupported synchronization resource type: $value',
      ),
    );
  }
}

enum SyncOperationKind {
  upsert('upsert'),
  delete('delete');

  const SyncOperationKind(this.apiValue);

  final String apiValue;

  static SyncOperationKind fromApiValue(String value) {
    return values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () => throw FormatException(
        'Unsupported synchronization operation: $value',
      ),
    );
  }
}

class PendingSyncOperation {
  PendingSyncOperation({
    required this.operationId,
    this.operation = SyncOperationKind.upsert,
    required this.resourceType,
    required this.resourceId,
    required this.baseRevision,
    required Map<String, Object?> content,
  }) : content = Map.unmodifiable(_copyJsonObject(content));

  final String operationId;
  final SyncOperationKind operation;
  final SyncResourceType resourceType;
  final String resourceId;
  final int baseRevision;
  final Map<String, Object?> content;

  String get resourceKey => '${resourceType.apiValue}:$resourceId';

  PendingSyncOperation copyWith({
    SyncOperationKind? operation,
    int? baseRevision,
    Map<String, Object?>? content,
  }) {
    return PendingSyncOperation(
      operationId: operationId,
      operation: operation ?? this.operation,
      resourceType: resourceType,
      resourceId: resourceId,
      baseRevision: baseRevision ?? this.baseRevision,
      content: content ?? this.content,
    );
  }

  factory PendingSyncOperation.fromJson(Map<String, Object?> json) {
    final operation = SyncOperationKind.fromApiValue(
      json['operation']! as String,
    );
    final baseRevision = json['baseRevision'];
    if (baseRevision is! int || baseRevision < 0) {
      throw const FormatException(
        'baseRevision must be a non-negative integer',
      );
    }
    return PendingSyncOperation(
      operationId: json['operationId']! as String,
      operation: operation,
      resourceType: SyncResourceType.fromApiValue(
        json['resourceType']! as String,
      ),
      resourceId: json['resourceId']! as String,
      baseRevision: baseRevision,
      content: switch (operation) {
        SyncOperationKind.upsert =>
          (json['content']! as Map<Object?, Object?>).cast<String, Object?>(),
        SyncOperationKind.delete =>
          json.containsKey('content')
              ? throw const FormatException(
                  'Delete synchronization operations must omit content.',
                )
              : const {},
      },
    );
  }

  Map<String, Object?> toJson() {
    return {
      'operationId': operationId,
      'operation': operation.apiValue,
      'resourceType': resourceType.apiValue,
      'resourceId': resourceId,
      'baseRevision': baseRevision,
      if (operation == SyncOperationKind.upsert) 'content': content,
    };
  }
}

class SyncCommitBatch {
  SyncCommitBatch({
    required this.idempotencyKey,
    required this.baseCursor,
    required List<PendingSyncOperation> operations,
    required this.createdAt,
  }) : operations = List.unmodifiable(operations);

  final String idempotencyKey;
  final String baseCursor;
  final List<PendingSyncOperation> operations;
  final DateTime createdAt;

  factory SyncCommitBatch.fromJson(Map<String, Object?> json) {
    return SyncCommitBatch(
      idempotencyKey: json['idempotencyKey']! as String,
      baseCursor: json['baseCursor']! as String,
      operations: (json['operations']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(PendingSyncOperation.fromJson)
          .toList(),
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'idempotencyKey': idempotencyKey,
      'baseCursor': baseCursor,
      'operations': operations.map((operation) => operation.toJson()).toList(),
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> toApiJson({required String deviceId}) {
    return {
      'deviceId': deviceId,
      'idempotencyKey': idempotencyKey,
      'baseCursor': baseCursor,
      'operations': operations.map((operation) => operation.toJson()).toList(),
    };
  }
}

class SyncOperationCommitResult {
  const SyncOperationCommitResult({
    required this.operationId,
    required this.revision,
  });

  final String operationId;
  final int revision;
}

class SyncStateSnapshot {
  SyncStateSnapshot({
    required this.lastAppliedCursor,
    required List<PendingSyncOperation> pendingOperations,
    required this.inFlightBatch,
  }) : pendingOperations = List.unmodifiable(pendingOperations);

  final String? lastAppliedCursor;
  final List<PendingSyncOperation> pendingOperations;
  final SyncCommitBatch? inFlightBatch;

  bool get hasPendingWork =>
      pendingOperations.isNotEmpty || inFlightBatch != null;
}

Map<String, Object?> _copyJsonObject(Map<String, Object?> value) {
  Object? copyValue(Object? input) {
    return switch (input) {
      null || bool() || String() || num() => input,
      List<Object?>() => input.map(copyValue).toList(),
      Map<Object?, Object?>() => {
        for (final entry in input.entries)
          entry.key as String: copyValue(entry.value),
      },
      _ => throw ArgumentError.value(
        input,
        'content',
        'Synchronization content must contain only JSON values.',
      ),
    };
  }

  return copyValue(value)! as Map<String, Object?>;
}
