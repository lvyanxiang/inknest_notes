import 'dart:io';

import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

class IncrementalSyncPushResult {
  const IncrementalSyncPushResult({
    required this.uploadedOperationCount,
    required this.preservedConflictCount,
  });

  final int uploadedOperationCount;
  final int preservedConflictCount;
}

class IncrementalSyncPushService {
  const IncrementalSyncPushService({
    required this.cloudClient,
    required this.rootDirectory,
  });

  final FirstSignInCloudClient cloudClient;
  final Directory rootDirectory;

  Future<IncrementalSyncPushResult> push({
    required String userId,
    required String deviceId,
  }) async {
    final stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    var uploaded = 0;
    var conflicts = 0;

    final initialState = await stateStore.loadSnapshot();
    if (initialState.lastAppliedCursor == null) {
      return const IncrementalSyncPushResult(
        uploadedOperationCount: 0,
        preservedConflictCount: 0,
      );
    }

    while (true) {
      final batch = await stateStore.prepareNextCommit();
      if (batch == null) break;
      final response = await cloudClient.commitSharedContent(
        deviceId: deviceId,
        idempotencyKey: batch.idempotencyKey,
        baseCursor: batch.baseCursor,
        operations: batch.operations
            .map((operation) => operation.toJson())
            .toList(),
      );
      _validateResponse(batch, response);
      for (final result in response.results) {
        await resourceMap.updateRemote(
          resourceType: SyncResourceType.fromApiValue(result.resourceType),
          remoteResourceId: result.resourceId,
          revision: result.revision,
          contentHash: result.contentHash,
        );
      }
      await stateStore.markCommitSucceeded(
        idempotencyKey: batch.idempotencyKey,
        results: [
          for (final result in response.results)
            SyncOperationCommitResult(
              operationId: result.operationId,
              revision: result.revision,
            ),
        ],
      );
      uploaded += batch.operations.length;
      conflicts += response.results
          .where((result) => result.outcome == 'conflict')
          .length;
    }
    return IncrementalSyncPushResult(
      uploadedOperationCount: uploaded,
      preservedConflictCount: conflicts,
    );
  }

  void _validateResponse(
    SyncCommitBatch batch,
    SyncContentCommitResult result,
  ) {
    final expected = {for (final item in batch.operations) item.operationId};
    final actual = {for (final item in result.results) item.operationId};
    if (result.idempotencyKey != batch.idempotencyKey ||
        result.results.length != batch.operations.length ||
        actual.length != result.results.length ||
        !expected.containsAll(actual) ||
        !actual.containsAll(expected)) {
      throw const FormatException(
        'Incremental commit response does not match the in-flight batch.',
      );
    }
  }
}
