import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';

enum SyncTombstoneRestoreFailure {
  alreadyRestored,
  unavailable,
  reconciliationRequired,
}

class SyncTombstoneRestoreException implements Exception {
  const SyncTombstoneRestoreException(this.failure);

  final SyncTombstoneRestoreFailure failure;
}

class SyncTombstoneRestoreResult {
  const SyncTombstoneRestoreResult({required this.pullResult});

  final IncrementalSyncPullResult pullResult;
}

abstract interface class SyncTombstoneRestoreService {
  Future<SyncTombstoneRestoreResult> restoreTombstone({
    required String userId,
    required String deviceId,
    required String tombstoneId,
  });
}

class ApiSyncTombstoneRestoreService implements SyncTombstoneRestoreService {
  const ApiSyncTombstoneRestoreService({
    required this.cloudClient,
    required this.pullService,
  });

  final SyncTombstoneCloudClient cloudClient;
  final IncrementalSyncPullService pullService;

  @override
  Future<SyncTombstoneRestoreResult> restoreTombstone({
    required String userId,
    required String deviceId,
    required String tombstoneId,
  }) async {
    try {
      final restored = await cloudClient.restoreSyncTombstone(tombstoneId);
      if (restored.state != 'restored' ||
          restored.resolution != 'restored_snapshot') {
        throw const FormatException(
          'Tombstone restore response does not confirm restoration.',
        );
      }
    } on InkNestApiException catch (error) {
      if (error.code == 'sync_tombstone_not_active' ||
          error.code == 'sync_tombstone_not_found') {
        final refreshed = await pullService.pull(
          userId: userId,
          deviceId: deviceId,
        );
        if ((refreshed.status == IncrementalSyncPullStatus.applied ||
                refreshed.status == IncrementalSyncPullStatus.upToDate) &&
            !refreshed.activeTombstones.any((item) => item.id == tombstoneId)) {
          return SyncTombstoneRestoreResult(pullResult: refreshed);
        }
        throw const SyncTombstoneRestoreException(
          SyncTombstoneRestoreFailure.alreadyRestored,
        );
      }
      throw const SyncTombstoneRestoreException(
        SyncTombstoneRestoreFailure.unavailable,
      );
    }

    final pullResult = await pullService.pull(
      userId: userId,
      deviceId: deviceId,
    );
    if ((pullResult.status != IncrementalSyncPullStatus.applied &&
            pullResult.status != IncrementalSyncPullStatus.upToDate) ||
        pullResult.activeTombstones.any((item) => item.id == tombstoneId)) {
      throw const SyncTombstoneRestoreException(
        SyncTombstoneRestoreFailure.reconciliationRequired,
      );
    }
    return SyncTombstoneRestoreResult(pullResult: pullResult);
  }
}
