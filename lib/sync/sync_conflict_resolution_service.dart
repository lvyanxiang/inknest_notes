import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

enum SyncConflictResolutionFailure {
  staleOriginal,
  alreadyResolved,
  unavailable,
  reconciliationRequired,
}

class SyncConflictResolutionException implements Exception {
  const SyncConflictResolutionException(this.failure);

  final SyncConflictResolutionFailure failure;
}

class SyncConflictResolutionResult {
  const SyncConflictResolutionResult({required this.pullResult});

  final IncrementalSyncPullResult pullResult;
}

abstract interface class SyncConflictResolutionService {
  Future<SyncConflictResolutionResult> resolveConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncConflictResolution resolution,
  });
}

class ApiSyncConflictResolutionService
    implements SyncConflictResolutionService {
  const ApiSyncConflictResolutionService({
    required this.cloudClient,
    required this.pullService,
  });

  final SyncConflictCloudClient cloudClient;
  final IncrementalSyncPullService pullService;

  @override
  Future<SyncConflictResolutionResult> resolveConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncConflictResolution resolution,
  }) async {
    CloudSyncConflict resolved;
    try {
      resolved = await cloudClient.resolveSyncConflict(
        conflictId: conflictId,
        resolution: resolution,
      );
    } on InkNestApiException catch (error) {
      if (error.code == 'sync_conflict_already_resolved' ||
          error.code == 'sync_conflict_not_found') {
        final refreshed = await pullService.pull(
          userId: userId,
          deviceId: deviceId,
        );
        if ((refreshed.status == IncrementalSyncPullStatus.applied ||
                refreshed.status == IncrementalSyncPullStatus.upToDate) &&
            !refreshed.pendingConflicts.any((item) => item.id == conflictId)) {
          return SyncConflictResolutionResult(pullResult: refreshed);
        }
      }
      throw SyncConflictResolutionException(switch (error.code) {
        'sync_conflict_resolution_stale' =>
          SyncConflictResolutionFailure.staleOriginal,
        'sync_conflict_already_resolved' || 'sync_conflict_not_found' =>
          SyncConflictResolutionFailure.alreadyResolved,
        _ => SyncConflictResolutionFailure.unavailable,
      });
    }
    if (resolved.isPending || resolved.resolution != resolution.apiValue) {
      throw const FormatException(
        'Conflict resolution response does not confirm the requested action.',
      );
    }

    final pullResult = await pullService.pull(
      userId: userId,
      deviceId: deviceId,
    );
    if (pullResult.status != IncrementalSyncPullStatus.applied &&
        pullResult.status != IncrementalSyncPullStatus.upToDate) {
      throw const SyncConflictResolutionException(
        SyncConflictResolutionFailure.reconciliationRequired,
      );
    }
    if (pullResult.pendingConflicts.any((item) => item.id == conflictId)) {
      // The endpoint is idempotent. Keeping the old local entry makes a retry
      // safe if its resolved change has not reached this Cursor yet.
      throw const SyncConflictResolutionException(
        SyncConflictResolutionFailure.reconciliationRequired,
      );
    }
    return SyncConflictResolutionResult(pullResult: pullResult);
  }
}
