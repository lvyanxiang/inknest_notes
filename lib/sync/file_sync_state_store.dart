import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:inknest_notes/sync/sync_state.dart';

typedef SyncIdFactory = String Function(String prefix);

class SyncStateFormatException extends FormatException {
  const SyncStateFormatException(super.message);
}

class SyncCursorUnavailableException extends StateError {
  SyncCursorUnavailableException()
    : super(
        'A synchronization Cursor must be saved before preparing a commit.',
      );
}

class SyncCommitStateException extends StateError {
  SyncCommitStateException(super.message);
}

class FileSyncStateStore {
  FileSyncStateStore({
    required Directory rootDirectory,
    required this.userId,
    required this.deviceId,
    SyncIdFactory? idFactory,
    DateTime Function()? clock,
  }) : _stateFile = File(
         '${rootDirectory.path}/sync/$userId/$deviceId/state.json',
       ),
       _idFactory = idFactory ?? _defaultIdFactory,
       _clock = clock ?? DateTime.now {
    _validateScopeSegment(userId, 'userId');
    _validateScopeSegment(deviceId, 'deviceId');
  }

  static const int currentFormatVersion = 1;

  final String userId;
  final String deviceId;
  final File _stateFile;
  final SyncIdFactory _idFactory;
  final DateTime Function() _clock;
  Future<void> _writeQueue = Future.value();
  int _temporaryFileCounter = 0;

  Future<SyncStateSnapshot> loadSnapshot() async {
    await _writeQueue.catchError((_) {});
    return (await _readState()).snapshot;
  }

  Future<void> markChangesPageApplied(String cursor) {
    if (cursor.isEmpty || cursor.trim() != cursor) {
      throw ArgumentError.value(cursor, 'cursor', 'Cursor must not be empty.');
    }
    return _mutate((state) {
      state.lastAppliedCursor = cursor;
    });
  }

  Future<PendingSyncOperation> enqueueUpsert({
    required SyncResourceType resourceType,
    required String resourceId,
    required int baseRevision,
    required Map<String, Object?> content,
  }) {
    if (resourceId.trim().isEmpty) {
      throw ArgumentError.value(
        resourceId,
        'resourceId',
        'Resource ID must not be empty.',
      );
    }
    if (baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'Base revision must be non-negative.',
      );
    }

    return _mutate((state) {
      final resourceKey = '${resourceType.apiValue}:$resourceId';
      final existingIndex = state.pendingOperations.indexWhere(
        (operation) => operation.resourceKey == resourceKey,
      );
      if (existingIndex != -1) {
        final updated = state.pendingOperations[existingIndex].copyWith(
          operation: SyncOperationKind.upsert,
          content: content,
          includesContent: true,
        );
        state.pendingOperations[existingIndex] = updated;
        return updated;
      }

      final operation = PendingSyncOperation(
        operationId: _idFactory('operation'),
        resourceType: resourceType,
        resourceId: resourceId,
        baseRevision: baseRevision,
        content: content,
      );
      state.pendingOperations.add(operation);
      return operation;
    });
  }

  Future<PendingSyncOperation> enqueueNotebookMetadata({
    required String resourceId,
    required int baseRevision,
    required Map<String, Object?> baseMetadata,
    required Map<String, Object?> metadata,
  }) {
    if (resourceId.trim().isEmpty || baseRevision < 0) {
      throw ArgumentError('Invalid notebook metadata synchronization state.');
    }
    return _mutate((state) {
      final resourceKey = '${SyncResourceType.notebook.apiValue}:$resourceId';
      final existingIndex = state.pendingOperations.indexWhere(
        (operation) => operation.resourceKey == resourceKey,
      );
      if (existingIndex != -1) {
        final existing = state.pendingOperations[existingIndex];
        final updated = existing.copyWith(
          operation: SyncOperationKind.upsert,
          metadata: metadata,
          baseMetadata: existing.baseMetadata ?? baseMetadata,
        );
        state.pendingOperations[existingIndex] = updated;
        return updated;
      }
      final operation = PendingSyncOperation(
        operationId: _idFactory('operation'),
        resourceType: SyncResourceType.notebook,
        resourceId: resourceId,
        baseRevision: baseRevision,
        content: const {},
        includesContent: false,
        metadata: metadata,
        baseMetadata: baseMetadata,
      );
      state.pendingOperations.add(operation);
      return operation;
    });
  }

  Future<PendingSyncOperation> enqueueDelete({
    required SyncResourceType resourceType,
    required String resourceId,
    required int baseRevision,
  }) {
    if (resourceId.trim().isEmpty) {
      throw ArgumentError.value(
        resourceId,
        'resourceId',
        'Resource ID must not be empty.',
      );
    }
    if (baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'Base revision must be non-negative.',
      );
    }

    return _mutate((state) {
      final resourceKey = '${resourceType.apiValue}:$resourceId';
      final existingIndex = state.pendingOperations.indexWhere(
        (operation) => operation.resourceKey == resourceKey,
      );
      if (existingIndex != -1) {
        final updated = state.pendingOperations[existingIndex].copyWith(
          operation: SyncOperationKind.delete,
          content: const {},
          includesContent: false,
        );
        state.pendingOperations[existingIndex] = updated;
        return updated;
      }

      final operation = PendingSyncOperation(
        operationId: _idFactory('operation'),
        operation: SyncOperationKind.delete,
        resourceType: resourceType,
        resourceId: resourceId,
        baseRevision: baseRevision,
        content: const {},
      );
      state.pendingOperations.add(operation);
      return operation;
    });
  }

  Future<SyncCommitBatch?> prepareNextCommit({int maxOperations = 100}) {
    if (maxOperations < 1 || maxOperations > 100) {
      throw ArgumentError.value(
        maxOperations,
        'maxOperations',
        'Batch size must be between 1 and 100.',
      );
    }

    return _mutate((state) {
      final existingBatch = state.inFlightBatch;
      if (existingBatch != null) {
        return existingBatch;
      }
      if (state.pendingOperations.isEmpty) {
        return null;
      }
      final cursor = state.lastAppliedCursor;
      if (cursor == null) {
        throw SyncCursorUnavailableException();
      }

      final operationCount = min(maxOperations, state.pendingOperations.length);
      final operations = state.pendingOperations.sublist(0, operationCount);
      state.pendingOperations.removeRange(0, operationCount);
      final batch = SyncCommitBatch(
        idempotencyKey: _idFactory('batch'),
        baseCursor: cursor,
        operations: operations,
        createdAt: _clock().toUtc(),
      );
      state.inFlightBatch = batch;
      return batch;
    });
  }

  Future<void> markCommitSucceeded({
    required String idempotencyKey,
    required List<SyncOperationCommitResult> results,
  }) {
    return _mutate((state) {
      final batch = state.inFlightBatch;
      if (batch == null || batch.idempotencyKey != idempotencyKey) {
        throw SyncCommitStateException(
          'The successful response does not match the in-flight batch.',
        );
      }
      final revisions = {
        for (final result in results) result.operationId: result.revision,
      };
      if (results.length != batch.operations.length ||
          revisions.length != batch.operations.length ||
          batch.operations.any(
            (operation) => !revisions.containsKey(operation.operationId),
          )) {
        throw SyncCommitStateException(
          'Every in-flight operation must have exactly one successful result.',
        );
      }
      if (results.any((result) => result.revision < 0)) {
        throw SyncCommitStateException(
          'A successful operation revision must be non-negative.',
        );
      }

      for (final committed in batch.operations) {
        final pendingIndex = state.pendingOperations.indexWhere(
          (operation) => operation.resourceKey == committed.resourceKey,
        );
        if (pendingIndex == -1) {
          continue;
        }
        state.pendingOperations[pendingIndex] = state
            .pendingOperations[pendingIndex]
            .copyWith(baseRevision: revisions[committed.operationId]!);
      }
      state.inFlightBatch = null;
    });
  }

  Future<T> _mutate<T>(T Function(_PersistedSyncState state) mutation) {
    final previousWrite = _writeQueue;
    final result = previousWrite.catchError((_) {}).then((_) async {
      final state = await _readState();
      final value = mutation(state);
      await _writeState(state);
      return value;
    });
    _writeQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<_PersistedSyncState> _readState() async {
    if (!await _stateFile.exists()) {
      return _PersistedSyncState.empty();
    }
    try {
      final decoded = jsonDecode(await _stateFile.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const SyncStateFormatException(
          'Synchronization state root must be a JSON object.',
        );
      }
      return _PersistedSyncState.fromJson(decoded);
    } on SyncStateFormatException {
      rethrow;
    } on Object catch (error) {
      throw SyncStateFormatException(
        'Synchronization state is invalid: ${error.runtimeType}',
      );
    }
  }

  Future<void> _writeState(_PersistedSyncState state) async {
    await _stateFile.parent.create(recursive: true);
    final temporaryFile = File(
      '${_stateFile.path}.tmp-${_clock().microsecondsSinceEpoch}-'
      '${_temporaryFileCounter++}',
    );
    await temporaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
    try {
      await temporaryFile.rename(_stateFile.path);
    } on FileSystemException {
      if (await _stateFile.exists()) {
        await _stateFile.delete();
      }
      await temporaryFile.rename(_stateFile.path);
    }
  }

  static String _defaultIdFactory(String prefix) {
    final random = Random.secure();
    final entropy = List.generate(
      4,
      (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '$prefix-$entropy';
  }

  static void _validateScopeSegment(String value, String name) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'Sync scope IDs must be safe non-empty path segments.',
      );
    }
  }
}

class _PersistedSyncState {
  _PersistedSyncState({
    required this.lastAppliedCursor,
    required this.pendingOperations,
    required this.inFlightBatch,
  });

  factory _PersistedSyncState.empty() {
    return _PersistedSyncState(
      lastAppliedCursor: null,
      pendingOperations: [],
      inFlightBatch: null,
    );
  }

  factory _PersistedSyncState.fromJson(Map<String, Object?> json) {
    if (json['formatVersion'] != FileSyncStateStore.currentFormatVersion) {
      throw const SyncStateFormatException(
        'Unsupported synchronization state format version.',
      );
    }
    final cursor = json['lastAppliedCursor'];
    if (cursor != null &&
        (cursor is! String || cursor.isEmpty || cursor.trim() != cursor)) {
      throw const SyncStateFormatException(
        'lastAppliedCursor must be a non-empty string or null.',
      );
    }
    return _PersistedSyncState(
      lastAppliedCursor: cursor as String?,
      pendingOperations:
          (json['pendingOperations'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>()
              .map(PendingSyncOperation.fromJson)
              .toList(),
      inFlightBatch: json['inFlightBatch'] == null
          ? null
          : SyncCommitBatch.fromJson(
              (json['inFlightBatch']! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
            ),
    );
  }

  String? lastAppliedCursor;
  final List<PendingSyncOperation> pendingOperations;
  SyncCommitBatch? inFlightBatch;

  SyncStateSnapshot get snapshot => SyncStateSnapshot(
    lastAppliedCursor: lastAppliedCursor,
    pendingOperations: pendingOperations,
    inFlightBatch: inFlightBatch,
  );

  Map<String, Object?> toJson() {
    return {
      'formatVersion': FileSyncStateStore.currentFormatVersion,
      if (lastAppliedCursor != null) 'lastAppliedCursor': lastAppliedCursor,
      'pendingOperations': pendingOperations
          .map((operation) => operation.toJson())
          .toList(),
      if (inFlightBatch != null) 'inFlightBatch': inFlightBatch!.toJson(),
    };
  }
}
