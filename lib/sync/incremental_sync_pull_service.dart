import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/shared_sync_apply_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_notebook_deletion_service.dart';
import 'package:inknest_notes/sync/sync_page_deletion_service.dart';

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
    this.appliedSharedResourceCount = 0,
    this.deletedNotebookCount = 0,
    this.confirmedLocalDeletionCount = 0,
    this.deletedPageCount = 0,
    this.confirmedLocalPageDeletionCount = 0,
    this.receivedConflictCount = 0,
    this.pendingConflicts = const [],
  });

  final IncrementalSyncPullStatus status;
  final int changeCount;
  final int downloadedNotebookCount;
  final int downloadedAssetCount;
  final int appliedSharedResourceCount;
  final int deletedNotebookCount;
  final int confirmedLocalDeletionCount;
  final int deletedPageCount;
  final int confirmedLocalPageDeletionCount;
  final int receivedConflictCount;
  final List<CloudSyncConflict> pendingConflicts;

  bool get changedLocalLibrary =>
      downloadedNotebookCount > 0 ||
      appliedSharedResourceCount > 0 ||
      deletedNotebookCount > 0 ||
      deletedPageCount > 0;
}

/// Pulls all currently available change pages without advancing the local
/// Cursor, then applies additive roots or continuous Revision-checked content
/// updates. Deletes, structural divergence, conflicts, and Tombstones leave
/// local data and the Cursor unchanged.
class IncrementalSyncPullService {
  const IncrementalSyncPullService({
    required this.repository,
    required this.cloudClient,
    required this.rootDirectory,
    this.mutationTracker,
  });

  final NotebookRepository repository;
  final FirstSignInCloudClient cloudClient;
  final Directory rootDirectory;
  final SyncMutationTracker? mutationTracker;

  Future<IncrementalSyncPullResult> pull({
    required String userId,
    required String deviceId,
  }) async {
    final stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    final conflictStore = FileSyncConflictStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    var pendingConflicts = await conflictStore.loadPending();
    final state = await stateStore.loadSnapshot();
    final initialCursor = state.lastAppliedCursor;
    if (initialCursor == null) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.notInitialized,
        pendingConflicts: pendingConflicts,
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
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.notInitialized,
          pendingConflicts: pendingConflicts,
        );
      }
    }
    if (state.hasPendingWork) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        pendingConflicts: pendingConflicts,
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
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.upToDate,
        pendingConflicts: pendingConflicts,
      );
    }

    final conflictOnly = changes.every(
      (change) =>
          change.resourceType == CloudSyncChangeResourceType.conflict &&
          change.operation == CloudSyncChangeOperation.upsert,
    );
    if (conflictOnly) {
      pendingConflicts = await conflictStore.applyChanges(changes);
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: changes.length,
        receivedConflictCount: changes
            .where((change) => change.payload?['status'] == 'pending')
            .length,
        pendingConflicts: pendingConflicts,
      );
    }

    final bootstrap = await cloudClient.bootstrap();
    final hasDeletionChanges = changes.any(
      (change) =>
          change.operation == CloudSyncChangeOperation.delete ||
          change.resourceType == CloudSyncChangeResourceType.tombstone,
    );
    if (hasDeletionChanges) {
      final deletionTypes = changes
          .where(
            (change) => change.operation == CloudSyncChangeOperation.delete,
          )
          .map((change) => change.resourceType)
          .toSet();
      SyncNotebookDeletionResult? notebookDeletion;
      SyncPageDeletionResult? pageDeletion;
      if (deletionTypes.length == 1 &&
          deletionTypes.single == CloudSyncChangeResourceType.notebook) {
        notebookDeletion =
            await SyncNotebookDeletionService(
              rootDirectory: rootDirectory,
            ).applyIfSafe(
              changes: changes,
              bootstrap: bootstrap,
              mappings: mappings,
              userId: userId,
              deviceId: deviceId,
            );
      } else if (deletionTypes.length == 1 &&
          deletionTypes.single == CloudSyncChangeResourceType.page) {
        pageDeletion =
            await SyncPageDeletionService(
              rootDirectory: rootDirectory,
            ).applyIfSafe(
              changes: changes,
              bootstrap: bootstrap,
              mappings: mappings,
              userId: userId,
              deviceId: deviceId,
            );
      }
      if (notebookDeletion == null && pageDeletion == null) {
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.requiresReconciliation,
          changeCount: changes.length,
          pendingConflicts: pendingConflicts,
        );
      }
      await resourceMap.replaceAll(
        await buildSyncResourceMappings(
          repository: repository,
          bootstrap: bootstrap,
        ),
        cloudAssetKeys: buildCloudAssetKeys(bootstrap),
      );
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: changes.length,
        deletedNotebookCount: notebookDeletion?.deletedNotebookCount ?? 0,
        confirmedLocalDeletionCount:
            notebookDeletion?.confirmedLocalDeletionCount ?? 0,
        deletedPageCount: pageDeletion?.deletedPageCount ?? 0,
        confirmedLocalPageDeletionCount:
            pageDeletion?.confirmedLocalPageDeletionCount ?? 0,
        pendingConflicts: pendingConflicts,
      );
    }
    final local = await readLocalSyncLibraryInventory(repository);
    final assessment = SyncBootstrapAssessment(
      local: local,
      cloud: bootstrap.inventory,
    );
    final hasCloudOnlyRoots =
        assessment.cloudOnlyFolderIds.isNotEmpty ||
        assessment.cloudOnlyNotebookIds.isNotEmpty;
    if (!hasCloudOnlyRoots) {
      final applyService = SharedSyncApplyService(repository: repository);
      Future<SharedSyncApplyResult?> applyShared() => applyService.applyIfSafe(
        changes: changes,
        bootstrap: bootstrap,
        mappings: mappings,
        resourceMap: resourceMap,
      );
      final sharedResult = mutationTracker == null
          ? await applyShared()
          : await mutationTracker!.runWithoutTracking(applyShared);
      if (sharedResult == null) {
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.requiresReconciliation,
          changeCount: changes.length,
          pendingConflicts: pendingConflicts,
        );
      }
      await resourceMap.replaceAll(
        await buildSyncResourceMappings(
          repository: repository,
          bootstrap: bootstrap,
        ),
        cloudAssetKeys: buildCloudAssetKeys(bootstrap),
      );
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: changes.length,
        appliedSharedResourceCount: sharedResult.appliedResourceCount,
        pendingConflicts: pendingConflicts,
      );
    }
    if (!_canApplyAdditively(
      changes: changes,
      bootstrap: bootstrap,
      assessment: assessment,
      currentDeviceId: deviceId,
    )) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        changeCount: changes.length,
        pendingConflicts: pendingConflicts,
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
      cloudAssetKeys: buildCloudAssetKeys(bootstrap),
    );
    await stateStore.markChangesPageApplied(cursor);
    return IncrementalSyncPullResult(
      status: IncrementalSyncPullStatus.applied,
      changeCount: changes.length,
      downloadedNotebookCount: restored.downloadedNotebookCount,
      downloadedAssetCount: restored.downloadedAssetCount,
      pendingConflicts: pendingConflicts,
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
