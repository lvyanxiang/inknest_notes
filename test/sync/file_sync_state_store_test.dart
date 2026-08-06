import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';

void main() {
  late Directory tempDirectory;
  late List<String> generatedIds;
  late FileSyncStateStore store;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('inknest-sync-test-');
    generatedIds = ['operation-1', 'batch-1', 'operation-2', 'batch-2'];
    store = FileSyncStateStore(
      rootDirectory: tempDirectory,
      userId: 'user-1',
      deviceId: 'device-1',
      idFactory: (_) => generatedIds.removeAt(0),
      clock: () => DateTime.utc(2026, 8, 6, 12),
    );
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'persists pending operations and opaque Cursor across restart',
    () async {
      await store.markChangesPageApplied('signed.cursor');
      await store.enqueueUpsert(
        resourceType: SyncResourceType.page,
        resourceId: 'page-1',
        baseRevision: 3,
        content: {
          'coordinateSpaceVersion': 1,
          'strokes': [
            {'id': 'stroke-1'},
          ],
        },
      );

      final reloaded = FileSyncStateStore(
        rootDirectory: tempDirectory,
        userId: 'user-1',
        deviceId: 'device-1',
      );
      final snapshot = await reloaded.loadSnapshot();

      expect(snapshot.lastAppliedCursor, 'signed.cursor');
      expect(snapshot.pendingOperations, hasLength(1));
      expect(snapshot.pendingOperations.single.operationId, 'operation-1');
      expect(snapshot.pendingOperations.single.baseRevision, 3);
      expect(
        snapshot.pendingOperations.single.content['coordinateSpaceVersion'],
        1,
      );
      expect(snapshot.inFlightBatch, isNull);

      final stateFile = File(
        '${tempDirectory.path}/sync/user-1/device-1/state.json',
      );
      final stateJson =
          jsonDecode(await stateFile.readAsString()) as Map<String, Object?>;
      expect(
        stateJson['formatVersion'],
        FileSyncStateStore.currentFormatVersion,
      );
    },
  );

  test(
    'coalesces unsent edits while preserving the first base revision',
    () async {
      final first = await store.enqueueUpsert(
        resourceType: SyncResourceType.notebook,
        resourceId: 'notebook-1',
        baseRevision: 7,
        content: {'title': 'First local edit'},
      );
      final second = await store.enqueueUpsert(
        resourceType: SyncResourceType.notebook,
        resourceId: 'notebook-1',
        baseRevision: 99,
        content: {'title': 'Latest local edit'},
      );
      final snapshot = await store.loadSnapshot();

      expect(second.operationId, first.operationId);
      expect(snapshot.pendingOperations, hasLength(1));
      expect(snapshot.pendingOperations.single.baseRevision, 7);
      expect(snapshot.pendingOperations.single.content, {
        'title': 'Latest local edit',
      });
    },
  );

  test('persists one exact in-flight request for safe network retry', () async {
    await store.markChangesPageApplied('cursor-before-commit');
    await store.enqueueUpsert(
      resourceType: SyncResourceType.page,
      resourceId: 'page-1',
      baseRevision: 0,
      content: {'strokes': <Object?>[]},
    );

    final firstBatch = await store.prepareNextCommit();
    final reloaded = FileSyncStateStore(
      rootDirectory: tempDirectory,
      userId: 'user-1',
      deviceId: 'device-1',
    );
    final retryBatch = await reloaded.prepareNextCommit();

    expect(firstBatch, isNotNull);
    expect(retryBatch, isNotNull);
    expect(retryBatch!.idempotencyKey, firstBatch!.idempotencyKey);
    expect(retryBatch.baseCursor, firstBatch.baseCursor);
    expect(retryBatch.toJson(), firstBatch.toJson());
    expect(retryBatch.toApiJson(deviceId: 'device-1'), {
      'deviceId': 'device-1',
      'idempotencyKey': 'batch-1',
      'baseCursor': 'cursor-before-commit',
      'operations': [
        {
          'operationId': 'operation-1',
          'operation': 'upsert',
          'resourceType': 'page',
          'resourceId': 'page-1',
          'baseRevision': 0,
          'content': {'strokes': <Object?>[]},
        },
      ],
    });
  });

  test(
    'keeps edits made during upload and rebases them after success',
    () async {
      await store.markChangesPageApplied('last-applied-pull-cursor');
      await store.enqueueUpsert(
        resourceType: SyncResourceType.page,
        resourceId: 'page-1',
        baseRevision: 4,
        content: {
          'strokes': ['first'],
        },
      );
      final batch = await store.prepareNextCommit();
      await store.enqueueUpsert(
        resourceType: SyncResourceType.page,
        resourceId: 'page-1',
        baseRevision: 4,
        content: {
          'strokes': ['first', 'while-uploading'],
        },
      );

      await store.markCommitSucceeded(
        idempotencyKey: batch!.idempotencyKey,
        results: const [
          SyncOperationCommitResult(operationId: 'operation-1', revision: 5),
        ],
      );
      final snapshot = await store.loadSnapshot();

      expect(snapshot.inFlightBatch, isNull);
      expect(snapshot.pendingOperations, hasLength(1));
      expect(snapshot.pendingOperations.single.operationId, 'operation-2');
      expect(snapshot.pendingOperations.single.baseRevision, 5);
      expect(snapshot.pendingOperations.single.content, {
        'strokes': ['first', 'while-uploading'],
      });
      expect(snapshot.lastAppliedCursor, 'last-applied-pull-cursor');
    },
  );

  test('does not clear a batch for a partial or mismatched response', () async {
    await store.markChangesPageApplied('cursor-1');
    await store.enqueueUpsert(
      resourceType: SyncResourceType.page,
      resourceId: 'page-1',
      baseRevision: 1,
      content: {'strokes': <Object?>[]},
    );
    final batch = await store.prepareNextCommit();

    await expectLater(
      store.markCommitSucceeded(
        idempotencyKey: 'another-batch',
        results: const [],
      ),
      throwsA(isA<SyncCommitStateException>()),
    );
    await expectLater(
      store.markCommitSucceeded(
        idempotencyKey: batch!.idempotencyKey,
        results: const [],
      ),
      throwsA(isA<SyncCommitStateException>()),
    );

    final snapshot = await store.loadSnapshot();
    expect(snapshot.inFlightBatch?.idempotencyKey, batch.idempotencyKey);
  });

  test('does not clear a batch for duplicate operation results', () async {
    await store.markChangesPageApplied('cursor-1');
    await store.enqueueUpsert(
      resourceType: SyncResourceType.page,
      resourceId: 'page-1',
      baseRevision: 1,
      content: {'strokes': <Object?>[]},
    );
    final batch = await store.prepareNextCommit();

    await expectLater(
      store.markCommitSucceeded(
        idempotencyKey: batch!.idempotencyKey,
        results: const [
          SyncOperationCommitResult(operationId: 'operation-1', revision: 2),
          SyncOperationCommitResult(operationId: 'operation-1', revision: 2),
        ],
      ),
      throwsA(isA<SyncCommitStateException>()),
    );

    final snapshot = await store.loadSnapshot();
    expect(snapshot.inFlightBatch?.idempotencyKey, batch.idempotencyKey);
  });

  test(
    'keeps offline edits and exact retry state across repeated restarts',
    () async {
      final offlineIds = [
        'offline-operation-1',
        'offline-operation-2',
        'offline-operation-3',
        'offline-batch-1',
        'offline-batch-2',
      ];
      final offlineStore = FileSyncStateStore(
        rootDirectory: tempDirectory,
        userId: 'offline-user',
        deviceId: 'offline-device',
        idFactory: (_) => offlineIds.removeAt(0),
        clock: () => DateTime.utc(2026, 8, 6, 13),
      );
      await offlineStore.markChangesPageApplied('cursor-before-offline');
      for (var index = 0; index < 3; index++) {
        await offlineStore.enqueueUpsert(
          resourceType: SyncResourceType.page,
          resourceId: 'offline-page-$index',
          baseRevision: index,
          content: {'offlineEdit': index},
        );
      }

      final afterOfflineRestart = FileSyncStateStore(
        rootDirectory: tempDirectory,
        userId: 'offline-user',
        deviceId: 'offline-device',
        idFactory: (_) => offlineIds.removeAt(0),
        clock: () => DateTime.utc(2026, 8, 6, 13),
      );
      final firstBatch = await afterOfflineRestart.prepareNextCommit(
        maxOperations: 2,
      );
      final afterResponseLoss = FileSyncStateStore(
        rootDirectory: tempDirectory,
        userId: 'offline-user',
        deviceId: 'offline-device',
        idFactory: (_) => offlineIds.removeAt(0),
        clock: () => DateTime.utc(2026, 8, 6, 13),
      );
      final retryBatch = await afterResponseLoss.prepareNextCommit(
        maxOperations: 2,
      );

      expect(firstBatch, isNotNull);
      expect(firstBatch!.operations, hasLength(2));
      expect(retryBatch!.toJson(), firstBatch.toJson());
      expect(
        (await afterResponseLoss.loadSnapshot()).lastAppliedCursor,
        'cursor-before-offline',
      );

      await afterResponseLoss.markCommitSucceeded(
        idempotencyKey: retryBatch.idempotencyKey,
        results: [
          for (final operation in retryBatch.operations)
            SyncOperationCommitResult(
              operationId: operation.operationId,
              revision: operation.baseRevision + 1,
            ),
        ],
      );
      final secondBatch = await afterResponseLoss.prepareNextCommit();

      expect(secondBatch, isNotNull);
      expect(secondBatch!.operations, hasLength(1));
      expect(secondBatch.operations.single.resourceId, 'offline-page-2');
      expect(
        (await afterResponseLoss.loadSnapshot()).lastAppliedCursor,
        'cursor-before-offline',
      );
    },
  );

  test(
    'requires a pulled Cursor before moving pending work in flight',
    () async {
      await store.enqueueUpsert(
        resourceType: SyncResourceType.page,
        resourceId: 'page-1',
        baseRevision: 0,
        content: {'strokes': <Object?>[]},
      );

      await expectLater(
        store.prepareNextCommit(),
        throwsA(isA<SyncCursorUnavailableException>()),
      );
      final snapshot = await store.loadSnapshot();
      expect(snapshot.pendingOperations, hasLength(1));
      expect(snapshot.inFlightBatch, isNull);
    },
  );

  test('isolates state by account and device', () async {
    await store.markChangesPageApplied('user-1-device-1');
    final otherDevice = FileSyncStateStore(
      rootDirectory: tempDirectory,
      userId: 'user-1',
      deviceId: 'device-2',
    );
    final otherUser = FileSyncStateStore(
      rootDirectory: tempDirectory,
      userId: 'user-2',
      deviceId: 'device-1',
    );

    expect((await otherDevice.loadSnapshot()).lastAppliedCursor, isNull);
    expect((await otherUser.loadSnapshot()).lastAppliedCursor, isNull);
  });

  test(
    'serializes concurrent local queue writes without losing work',
    () async {
      final operationIds = List.generate(12, (index) => 'concurrent-$index');
      final concurrentStore = FileSyncStateStore(
        rootDirectory: tempDirectory,
        userId: 'user-concurrent',
        deviceId: 'device-1',
        idFactory: (_) => operationIds.removeAt(0),
      );

      await Future.wait([
        for (var index = 0; index < 12; index++)
          concurrentStore.enqueueUpsert(
            resourceType: SyncResourceType.page,
            resourceId: 'page-$index',
            baseRevision: index,
            content: {'index': index},
          ),
      ]);

      final snapshot = await concurrentStore.loadSnapshot();
      expect(snapshot.pendingOperations, hasLength(12));
      expect(
        snapshot.pendingOperations.map((operation) => operation.resourceId),
        [for (var index = 0; index < 12; index++) 'page-$index'],
      );
    },
  );

  test('rejects corrupted state instead of replacing it', () async {
    final stateFile = File(
      '${tempDirectory.path}/sync/user-1/device-1/state.json',
    );
    await stateFile.parent.create(recursive: true);
    await stateFile.writeAsString('{not-json', flush: true);

    await expectLater(
      store.loadSnapshot(),
      throwsA(isA<SyncStateFormatException>()),
    );
    expect(await stateFile.readAsString(), '{not-json');
  });
}
