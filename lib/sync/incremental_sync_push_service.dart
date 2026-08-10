import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/local_sync_asset_inventory.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

class IncrementalSyncPushResult {
  const IncrementalSyncPushResult({
    required this.uploadedOperationCount,
    required this.preservedConflictCount,
    this.preservedDeleteEditCount = 0,
  });

  final int uploadedOperationCount;
  final int preservedConflictCount;
  final int preservedDeleteEditCount;
}

class IncrementalSyncPushException implements Exception {
  const IncrementalSyncPushException({required this.pendingOperationCount});

  final int pendingOperationCount;
}

class IncrementalSyncPushService {
  const IncrementalSyncPushService({
    required this.cloudClient,
    required this.repository,
    required this.rootDirectory,
  });

  final FirstSignInCloudClient cloudClient;
  final NotebookRepository repository;
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
    var deleteEditConflicts = 0;

    final initialState = await stateStore.loadSnapshot();
    if (initialState.lastAppliedCursor == null) {
      return const IncrementalSyncPushResult(
        uploadedOperationCount: 0,
        preservedConflictCount: 0,
      );
    }

    try {
      await _uploadMissingAssets(
        resourceMap,
        operations: [
          ...initialState.pendingOperations,
          ...?initialState.inFlightBatch?.operations,
        ],
      );
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
        final operationsById = {
          for (final operation in batch.operations)
            operation.operationId: operation,
        };
        for (final result in response.results) {
          final operation = operationsById[result.operationId]!;
          if (operation.operation == SyncOperationKind.upsert &&
              operation.metadata == null) {
            await resourceMap.updateRemote(
              resourceType: SyncResourceType.fromApiValue(result.resourceType),
              remoteResourceId: result.resourceId,
              revision: result.revision,
              contentHash: result.contentHash,
            );
          }
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
        for (final result in response.results) {
          final operation = operationsById[result.operationId]!;
          if (result.outcome == 'conflict' &&
              operation.metadata != null &&
              operation.baseMetadata != null) {
            await stateStore.enqueueNotebookMetadata(
              resourceId: operation.resourceId,
              baseRevision: result.revision,
              baseMetadata: operation.baseMetadata!,
              metadata: operation.metadata!,
            );
          }
        }
        uploaded += batch.operations.length;
        conflicts += response.results
            .where(
              (result) =>
                  result.outcome == 'conflict' ||
                  result.outcome == 'delete_conflict',
            )
            .length;
        deleteEditConflicts += response.results
            .where((result) => result.outcome == 'delete_conflict')
            .length;
      }
    } on Object {
      final failedState = await stateStore.loadSnapshot();
      throw IncrementalSyncPushException(
        pendingOperationCount:
            failedState.pendingOperations.length +
            (failedState.inFlightBatch?.operations.length ?? 0),
      );
    }
    return IncrementalSyncPushResult(
      uploadedOperationCount: uploaded,
      preservedConflictCount: conflicts,
      preservedDeleteEditCount: deleteEditConflicts,
    );
  }

  Future<void> _uploadMissingAssets(
    FileSyncResourceMapStore resourceMap, {
    required List<PendingSyncOperation> operations,
  }) async {
    final mappings = await resourceMap.load();
    final mappedNotebookIds = _notebookIdsForContentOperations(
      mappings,
      operations,
    );
    final localAssets = await collectLocalSyncAssets(
      repository,
      notebookIds: mappedNotebookIds,
      knownCloudAssetKeys: await resourceMap.loadCloudAssetKeys(),
    );
    if (localAssets.isEmpty) return;

    for (final asset in localAssets) {
      try {
        final session = await cloudClient.createAssetUploadSession(asset);
        await cloudClient.uploadAssetFile(session, asset);
        await cloudClient.completeAssetUpload(session.uploadId);
      } on InkNestApiException catch (error) {
        if (error.code != 'asset_already_exists') rethrow;
      }
    }

    final bootstrap = await cloudClient.bootstrap();
    final cloudAssets = {for (final asset in bootstrap.assets) asset.id: asset};
    for (final local in localAssets) {
      final cloud = cloudAssets[local.id];
      if (cloud == null ||
          cloud.notebookId != local.notebookId ||
          cloud.kind != local.kind ||
          cloud.originalFilename != local.filename ||
          cloud.relativePath != local.relativePath ||
          cloud.contentType != local.contentType ||
          cloud.byteSize != local.byteSize ||
          cloud.sha256 != local.sha256) {
        throw StateError('Cloud attachment verification failed.');
      }
    }
    await resourceMap.addCloudAssetKeys(
      localAssets.map(
        (asset) => cloudAssetSyncKey(asset.notebookId, asset.relativePath),
      ),
    );
  }

  Set<String> _notebookIdsForContentOperations(
    List<SyncResourceMapping> mappings,
    List<PendingSyncOperation> operations,
  ) {
    final mappedByRemoteKey = {
      for (final mapping in mappings)
        '${mapping.resourceType.apiValue}:${mapping.remoteResourceId}': mapping,
    };
    final notebookIds = <String>{};
    for (final operation in operations) {
      if (operation.operation != SyncOperationKind.upsert ||
          !operation.includesContent) {
        continue;
      }
      final mapping = mappedByRemoteKey[operation.resourceKey];
      if (mapping == null) continue;
      final localKey = mapping.localKey;
      switch (mapping.resourceType) {
        case SyncResourceType.notebook:
          if (localKey.startsWith('notebook:')) {
            notebookIds.add(localKey.substring('notebook:'.length));
          }
        case SyncResourceType.page:
          if (localKey.startsWith('page:')) {
            final separator = localKey.lastIndexOf(':');
            if (separator > 'page:'.length) {
              notebookIds.add(localKey.substring('page:'.length, separator));
            }
          }
        case SyncResourceType.infiniteCanvas:
          if (localKey.startsWith('infinite_canvas:')) {
            notebookIds.add(localKey.substring('infinite_canvas:'.length));
          }
        case SyncResourceType.folder:
          break;
      }
    }
    return notebookIds;
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
