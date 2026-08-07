import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/shared_sync_apply_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_folder_deletion_service.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_restore_snapshot.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_notebook_deletion_service.dart';
import 'package:inknest_notes/sync/sync_page_deletion_service.dart';
import 'package:inknest_notes/sync/sync_page_structure_service.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';
import 'package:inknest_notes/sync/sync_state.dart';

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
    this.deletedFolderCount = 0,
    this.confirmedLocalFolderDeletionCount = 0,
    this.receivedConflictCount = 0,
    this.pendingConflicts = const [],
    this.activeTombstones = const [],
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
  final int deletedFolderCount;
  final int confirmedLocalFolderDeletionCount;
  final int receivedConflictCount;
  final List<CloudSyncConflict> pendingConflicts;
  final List<CloudSyncTombstone> activeTombstones;

  bool get changedLocalLibrary =>
      downloadedNotebookCount > 0 ||
      appliedSharedResourceCount > 0 ||
      deletedNotebookCount > 0 ||
      deletedPageCount > 0 ||
      deletedFolderCount > 0;
}

/// Pulls all currently available change pages without advancing the local
/// Cursor, then applies additive roots or continuous Revision-checked content
/// updates. Supported notebook/trailing-page deletes, conflict metadata, and
/// Tombstones are applied durably; unsafe structural divergence leaves local
/// data and the Cursor unchanged.
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
    final tombstoneStore = FileSyncTombstoneStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    var activeTombstones = await tombstoneStore.loadActive();
    final state = await stateStore.loadSnapshot();
    final initialCursor = state.lastAppliedCursor;
    if (initialCursor == null) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.notInitialized,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
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
      if (local.notebookIds.isNotEmpty) {
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.notInitialized,
          pendingConflicts: pendingConflicts,
          activeTombstones: activeTombstones,
        );
      }
    }
    if (state.hasPendingWork) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }

    var cursor = initialCursor;
    final allChanges = <CloudSyncChange>[];
    for (var pageNumber = 0; pageNumber < 100; pageNumber++) {
      final page = await cloudClient.listChanges(cursor: cursor, limit: 500);
      allChanges.addAll(page.changes);
      cursor = page.nextCursor;
      if (!page.hasMore) break;
      if (pageNumber == 99) {
        throw StateError('Incremental synchronization exceeded 100 pages.');
      }
    }

    if (allChanges.isEmpty) {
      final canvasesWithoutMetadata = mappings
          .where(
            (mapping) =>
                mapping.resourceType == SyncResourceType.infiniteCanvas &&
                mapping.infiniteCanvasMetadata == null,
          )
          .toList();
      if (canvasesWithoutMetadata.isNotEmpty) {
        final bootstrap = await cloudClient.bootstrap();
        for (final mapping in canvasesWithoutMetadata) {
          CloudSyncInfiniteCanvas? cloud;
          for (final candidate in bootstrap.infiniteCanvases) {
            if (candidate.id == mapping.remoteResourceId) {
              cloud = candidate;
              break;
            }
          }
          if (cloud == null ||
              cloud.revision != mapping.revision ||
              cloud.contentHash != mapping.contentHash) {
            return IncrementalSyncPullResult(
              status: IncrementalSyncPullStatus.requiresReconciliation,
              pendingConflicts: pendingConflicts,
              activeTombstones: activeTombstones,
            );
          }
          await resourceMap.updateRemote(
            resourceType: mapping.resourceType,
            remoteResourceId: mapping.remoteResourceId,
            revision: mapping.revision,
            contentHash: mapping.contentHash,
            infiniteCanvasMetadata: {'background': cloud.background},
          );
        }
      }
      if (cursor != initialCursor) {
        await stateStore.markChangesPageApplied(cursor);
      }
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.upToDate,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }

    final conflictChanges = allChanges
        .where(
          (change) =>
              change.resourceType == CloudSyncChangeResourceType.conflict,
        )
        .toList();
    final tombstoneChanges = allChanges
        .where(
          (change) =>
              change.resourceType == CloudSyncChangeResourceType.tombstone,
        )
        .toList();
    if (conflictChanges.any(
      (change) =>
          change.operation != CloudSyncChangeOperation.upsert ||
          change.payload == null,
    )) {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        changeCount: allChanges.length,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }
    final parsedTombstones = <String, CloudSyncTombstone>{};
    try {
      for (final change in tombstoneChanges) {
        if (change.operation != CloudSyncChangeOperation.upsert ||
            change.payload == null) {
          throw const FormatException('Invalid Tombstone change operation.');
        }
        final tombstone = CloudSyncTombstone.fromJson(change.payload!);
        if (tombstone.id != change.resourceId) {
          throw const FormatException('Tombstone change ID mismatch.');
        }
        parsedTombstones[change.changeId] = tombstone;
      }
    } on FormatException {
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.requiresReconciliation,
        changeCount: allChanges.length,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }
    final changes = allChanges
        .where(
          (change) =>
              change.resourceType != CloudSyncChangeResourceType.conflict &&
              change.resourceType != CloudSyncChangeResourceType.tombstone,
        )
        .toList();
    final receivedConflictCount = conflictChanges
        .where((change) => change.payload?['status'] == 'pending')
        .length;
    if (changes.isEmpty) {
      pendingConflicts = await conflictStore.applyChanges(conflictChanges);
      if (tombstoneChanges.isNotEmpty) {
        activeTombstones = await tombstoneStore.applyChanges(tombstoneChanges);
      }
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: allChanges.length,
        receivedConflictCount: receivedConflictCount,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }

    final bootstrap = await cloudClient.bootstrap();
    final hasDeletionChanges = changes.any(
      (change) =>
          change.operation == CloudSyncChangeOperation.delete ||
          change.resourceType == CloudSyncChangeResourceType.tombstone,
    );
    if (hasDeletionChanges) {
      final deletionChanges = [
        ...changes,
        for (final change in tombstoneChanges)
          if (parsedTombstones[change.changeId]?.isActive ?? false) change,
      ];
      final deletionTypes = changes
          .where(
            (change) => change.operation == CloudSyncChangeOperation.delete,
          )
          .map((change) => change.resourceType)
          .toSet();
      SyncNotebookDeletionResult? notebookDeletion;
      SyncPageDeletionResult? pageDeletion;
      SyncFolderDeletionResult? folderDeletion;
      if (deletionTypes.length == 1 &&
          deletionTypes.single == CloudSyncChangeResourceType.notebook) {
        notebookDeletion =
            await SyncNotebookDeletionService(
              rootDirectory: rootDirectory,
            ).applyIfSafe(
              changes: deletionChanges,
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
              changes: deletionChanges,
              bootstrap: bootstrap,
              mappings: mappings,
              userId: userId,
              deviceId: deviceId,
            );
      } else if (deletionTypes.length == 1 &&
          deletionTypes.single == CloudSyncChangeResourceType.folder) {
        Future<SyncFolderDeletionResult?> applyFolderDeletion() =>
            SyncFolderDeletionService(repository: repository).applyIfSafe(
              changes: deletionChanges,
              bootstrap: bootstrap,
              mappings: mappings,
              resourceMap: resourceMap,
              deviceId: deviceId,
            );
        folderDeletion = mutationTracker == null
            ? await applyFolderDeletion()
            : await mutationTracker!.runWithoutTracking(applyFolderDeletion);
      }
      if (notebookDeletion == null &&
          pageDeletion == null &&
          folderDeletion == null) {
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.requiresReconciliation,
          changeCount: allChanges.length,
          pendingConflicts: pendingConflicts,
          activeTombstones: activeTombstones,
        );
      }
      await resourceMap.replaceAll(
        await buildSyncResourceMappings(
          repository: repository,
          bootstrap: bootstrap,
        ),
        cloudAssetKeys: buildCloudAssetKeys(bootstrap),
      );
      if (conflictChanges.isNotEmpty) {
        pendingConflicts = await conflictStore.applyChanges(conflictChanges);
      }
      if (tombstoneChanges.isNotEmpty) {
        activeTombstones = await tombstoneStore.applyChanges(tombstoneChanges);
      }
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: allChanges.length,
        deletedNotebookCount: notebookDeletion?.deletedNotebookCount ?? 0,
        confirmedLocalDeletionCount:
            notebookDeletion?.confirmedLocalDeletionCount ?? 0,
        deletedPageCount: pageDeletion?.deletedPageCount ?? 0,
        confirmedLocalPageDeletionCount:
            pageDeletion?.confirmedLocalPageDeletionCount ?? 0,
        deletedFolderCount: folderDeletion?.deletedFolderCount ?? 0,
        confirmedLocalFolderDeletionCount:
            folderDeletion?.confirmedLocalFolderDeletionCount ?? 0,
        receivedConflictCount: receivedConflictCount,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }
    if (tombstoneChanges.isNotEmpty &&
        changes.every(
          (change) =>
              change.resourceType == CloudSyncChangeResourceType.page &&
              change.operation == CloudSyncChangeOperation.upsert,
        )) {
      Future<SyncPageStructureResult?> applyRestoration() =>
          SyncPageStructureService(
            repository: repository,
          ).applyRestorationIfSafe(
            changes: changes,
            bootstrap: bootstrap,
            mappings: mappings,
            resourceMap: resourceMap,
            changedTombstones: parsedTombstones.values,
          );
      final restored = mutationTracker == null
          ? await applyRestoration()
          : await mutationTracker!.runWithoutTracking(applyRestoration);
      if (restored != null) {
        await resourceMap.replaceAll(
          await buildSyncResourceMappings(
            repository: repository,
            bootstrap: bootstrap,
          ),
          cloudAssetKeys: buildCloudAssetKeys(bootstrap),
        );
        if (conflictChanges.isNotEmpty) {
          pendingConflicts = await conflictStore.applyChanges(conflictChanges);
        }
        activeTombstones = await tombstoneStore.applyChanges(tombstoneChanges);
        await stateStore.markChangesPageApplied(cursor);
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.applied,
          changeCount: allChanges.length,
          appliedSharedResourceCount: restored.restoredPageCount,
          receivedConflictCount: receivedConflictCount,
          pendingConflicts: pendingConflicts,
          activeTombstones: activeTombstones,
        );
      }
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
          changeCount: allChanges.length,
          pendingConflicts: pendingConflicts,
          activeTombstones: activeTombstones,
        );
      }
      await resourceMap.replaceAll(
        await buildSyncResourceMappings(
          repository: repository,
          bootstrap: bootstrap,
        ),
        cloudAssetKeys: buildCloudAssetKeys(bootstrap),
      );
      if (conflictChanges.isNotEmpty) {
        pendingConflicts = await conflictStore.applyChanges(conflictChanges);
      }
      if (tombstoneChanges.isNotEmpty) {
        activeTombstones = await tombstoneStore.applyChanges(tombstoneChanges);
      }
      await stateStore.markChangesPageApplied(cursor);
      return IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: allChanges.length,
        appliedSharedResourceCount: sharedResult.appliedResourceCount,
        receivedConflictCount: receivedConflictCount,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
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
        changeCount: allChanges.length,
        pendingConflicts: pendingConflicts,
        activeTombstones: activeTombstones,
      );
    }

    return withSyncRestoreSnapshot(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
      action: () async {
        final restored =
            await BootstrapRestoreService(
              rootDirectory: rootDirectory,
              assetClient: cloudClient,
              syncStateStore: stateStore,
            ).downloadAndApplyCloudOnly(
              bootstrap: bootstrap,
              assessment: assessment,
              persistCursor: false,
            );
        await resourceMap.replaceAll(
          await buildSyncResourceMappings(
            repository: repository,
            bootstrap: bootstrap,
          ),
          cloudAssetKeys: buildCloudAssetKeys(bootstrap),
        );
        if (conflictChanges.isNotEmpty) {
          pendingConflicts = await conflictStore.applyChanges(conflictChanges);
        }
        if (tombstoneChanges.isNotEmpty) {
          activeTombstones = await tombstoneStore.applyChanges(
            tombstoneChanges,
          );
        }
        await stateStore.markChangesPageApplied(cursor);
        return IncrementalSyncPullResult(
          status: IncrementalSyncPullStatus.applied,
          changeCount: allChanges.length,
          downloadedNotebookCount: restored.downloadedNotebookCount,
          downloadedAssetCount: restored.downloadedAssetCount,
          receivedConflictCount: receivedConflictCount,
          pendingConflicts: pendingConflicts,
          activeTombstones: activeTombstones,
        );
      },
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
