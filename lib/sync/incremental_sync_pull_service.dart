import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';

enum IncrementalSyncPullStatus {
  notInitialized,
  upToDate,
  applied,
  requiresReconciliation,
}

class IncrementalSyncPullResult {
  const IncrementalSyncPullResult({
    required this.status,
    this.changeCount = 0,
    this.downloadedNotebookCount = 0,
    this.downloadedAssetCount = 0,
  });

  final IncrementalSyncPullStatus status;
  final int changeCount;
  final int downloadedNotebookCount;
  final int downloadedAssetCount;

  bool get changedLocalLibrary => downloadedNotebookCount > 0;
}

/// Pulls all currently available change pages without advancing the local
/// Cursor, then applies only changes that are provably additive.
///
/// Existing local resources, deletes, conflicts, and Tombstones require the
/// later Revision-aware reconciliation slice. They never overwrite local data
/// and leave the Cursor unchanged.
class IncrementalSyncPullService {
  const IncrementalSyncPullService({
    required this.repository,
    required this.cloudClient,
    required this.rootDirectory,
  });

  final NotebookRepository repository;
  final FirstSignInCloudClient cloudClient;
  final Directory rootDirectory;

  Future<IncrementalSyncPullResult> pull({
    required String userId,
    required String deviceId,
  }) async {
    final stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    final state = await stateStore.loadSnapshot();
    final initialCursor = state.lastAppliedCursor;
    if (initialCursor == null) {
      return const IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.notInitialized,
      );
    }
    final resourceMap = FileSyncResourceMapStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    final mappings = await resourceMap.load();
    if (mappings.isEmpty) {
      final local = await readLocalSyncLibraryInventory(repository);
      if (local.hasLibrary) {
        return const IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.notInitialized,
        );
      }
    }
    if (state.hasPendingWork) {
      return const IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
      );
    }

    var cursor = initialCursor;
    final changes = <CloudSyncChange>[];
    for (var pageNumber = 0; pageNumber < 100; pageNumber++) {
      final page = await cloudClient.listChanges(cursor: cursor, limit: 500);
      changes.addAll(page.changes);
      cursor = page.nextCursor;
      if (!page.hasMore) break;
      if (pageNumber == 99) {
        throw StateError('Incremental synchronization exceeded 100 pages.');
      }
    }

    if (changes.isEmpty) {
      if (cursor != initialCursor) {
        await stateStore.markChangesPageApplied(cursor);
      }
      return const IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.upToDate,
      );
    }

    final bootstrap = await cloudClient.bootstrap();
    final local = await readLocalSyncLibraryInventory(repository);
    final assessment = SyncBootstrapAssessment(
      local: local,
      cloud: bootstrap.inventory,
    );
    if (!_canApplyAdditively(
      changes: changes,
      bootstrap: bootstrap,
      assessment: assessment,
      currentDeviceId: deviceId,
    )) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        changeCount: changes.length,
      );
    }

    final restored = await BootstrapRestoreService(
      rootDirectory: rootDirectory,
      assetClient: cloudClient,
      syncStateStore: stateStore,
    ).downloadAndApplyCloudOnly(bootstrap: bootstrap, assessment: assessment);
    await resourceMap.replaceAll(
      await buildSyncResourceMappings(
        repository: repository,
        bootstrap: bootstrap,
      ),
    );
    await stateStore.markChangesPageApplied(cursor);
    return IncrementalSyncPullResult(
      status: IncrementalSyncPullStatus.applied,
      changeCount: changes.length,
      downloadedNotebookCount: restored.downloadedNotebookCount,
      downloadedAssetCount: restored.downloadedAssetCount,
    );
  }

  bool _canApplyAdditively({
    required List<CloudSyncChange> changes,
    required CloudSyncBootstrap bootstrap,
    required SyncBootstrapAssessment assessment,
    required String currentDeviceId,
  }) {
    final pages = {for (final item in bootstrap.pages) item.id: item};
    final canvases = {
      for (final item in bootstrap.infiniteCanvases) item.id: item,
    };
    final assets = {for (final item in bootstrap.assets) item.id: item};
    final referencedCloudOnlyFolders = <String>{};
    final referencedCloudOnlyNotebooks = <String>{};

    for (final change in changes) {
      if (change.deviceId == currentDeviceId) continue;
      if (change.operation != CloudSyncChangeOperation.upsert) return false;
      final canApply = switch (change.resourceType) {
        CloudSyncChangeResourceType.folder =>
          assessment.cloudOnlyFolderIds.contains(change.resourceId),
        CloudSyncChangeResourceType.notebook =>
          assessment.cloudOnlyNotebookIds.contains(change.resourceId),
        CloudSyncChangeResourceType.page => _belongsToCloudOnlyNotebook(
          pages[change.resourceId]?.notebookId,
          assessment,
        ),
        CloudSyncChangeResourceType.infiniteCanvas =>
          _belongsToCloudOnlyNotebook(
            canvases[change.resourceId]?.notebookId,
            assessment,
          ),
        CloudSyncChangeResourceType.asset => _belongsToCloudOnlyNotebook(
          assets[change.resourceId]?.notebookId,
          assessment,
        ),
        CloudSyncChangeResourceType.conflict ||
        CloudSyncChangeResourceType.tombstone => false,
      };
      if (!canApply) return false;
      switch (change.resourceType) {
        case CloudSyncChangeResourceType.folder:
          referencedCloudOnlyFolders.add(change.resourceId);
        case CloudSyncChangeResourceType.notebook:
          referencedCloudOnlyNotebooks.add(change.resourceId);
        case CloudSyncChangeResourceType.page:
          referencedCloudOnlyNotebooks.add(
            pages[change.resourceId]!.notebookId,
          );
        case CloudSyncChangeResourceType.infiniteCanvas:
          referencedCloudOnlyNotebooks.add(
            canvases[change.resourceId]!.notebookId,
          );
        case CloudSyncChangeResourceType.asset:
          referencedCloudOnlyNotebooks.add(
            assets[change.resourceId]!.notebookId,
          );
        case CloudSyncChangeResourceType.conflict:
        case CloudSyncChangeResourceType.tombstone:
          return false;
      }
    }
    return referencedCloudOnlyFolders.containsAll(
          assessment.cloudOnlyFolderIds,
        ) &&
        referencedCloudOnlyNotebooks.containsAll(
          assessment.cloudOnlyNotebookIds,
        );
  }

  bool _belongsToCloudOnlyNotebook(
    String? notebookId,
    SyncBootstrapAssessment assessment,
  ) {
    return notebookId != null &&
        assessment.cloudOnlyNotebookIds.contains(notebookId);
  }
}
