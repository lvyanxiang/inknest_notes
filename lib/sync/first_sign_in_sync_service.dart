import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/local_sync_asset_inventory.dart';
import 'package:inknest_notes/sync/signed_out_sync_reconciliation_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_restore_snapshot.dart';
import 'package:inknest_notes/sync/sync_tombstone_restore_service.dart';
import 'package:inknest_notes/sync/sync_structural_conflicts.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_conflict_resolution_service.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

class FirstSignInSyncPreview {
  const FirstSignInSyncPreview({
    required this.bootstrap,
    required this.assessment,
    required this.plan,
  });

  final CloudSyncBootstrap bootstrap;
  final SyncBootstrapAssessment assessment;
  final SyncMergePlan plan;

  bool get canRestoreCloudOnly =>
      assessment.presence == SyncLibraryPresence.cloudOnly;

  bool get canUploadLocalOnly =>
      assessment.presence == SyncLibraryPresence.localOnly;

  bool get canMergeMixed =>
      assessment.presence == SyncLibraryPresence.localAndCloud;
}

class LocalMergeUploadResult {
  const LocalMergeUploadResult({
    required this.uploadedNotebookCount,
    required this.uploadedAssetCount,
  });

  final int uploadedNotebookCount;
  final int uploadedAssetCount;
}

class MixedLibraryMergeResult {
  const MixedLibraryMergeResult({
    required this.uploadedNotebookCount,
    required this.downloadedNotebookCount,
    required this.transferredAssetCount,
    required this.preservedConflictCount,
    this.pendingConflicts = const [],
  });

  final int uploadedNotebookCount;
  final int downloadedNotebookCount;
  final int transferredAssetCount;
  final int preservedConflictCount;
  final List<CloudSyncConflict> pendingConflicts;
}

abstract interface class FirstSignInSyncService {
  Future<IncrementalSyncPushResult> pushIncremental({
    required String userId,
    required String deviceId,
  });

  Future<IncrementalSyncPullResult> pullIncremental({
    required String userId,
    required String deviceId,
  });

  Future<FirstSignInSyncPreview> inspect();

  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  });

  Future<LocalMergeUploadResult> uploadLocalOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  });

  Future<MixedLibraryMergeResult> mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  });
}

class ApiFirstSignInSyncService
    implements
        FirstSignInSyncService,
        SyncConflictResolutionService,
        SyncTombstoneRestoreService,
        SyncStructuralConflictResolutionService {
  const ApiFirstSignInSyncService({
    required this.repository,
    required this.apiClient,
    required this.rootDirectory,
    this.mutationTracker,
  });

  final NotebookRepository repository;
  final FirstSignInCloudClient apiClient;
  final Directory rootDirectory;
  final SyncMutationTracker? mutationTracker;

  @override
  Future<IncrementalSyncPushResult> pushIncremental({
    required String userId,
    required String deviceId,
  }) async {
    final pushService = IncrementalSyncPushService(
      cloudClient: apiClient,
      repository: repository,
      rootDirectory: rootDirectory,
    );
    final initial = await pushService.push(userId: userId, deviceId: deviceId);
    var uploadedOperationCount = initial.uploadedOperationCount;
    var preservedConflictCount = initial.preservedConflictCount;
    var preservedDeleteEditCount = initial.preservedDeleteEditCount;
    final state = await FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    ).loadSnapshot();
    if (state.lastAppliedCursor == null) {
      return initial;
    }

    final tracker = mutationTracker;
    if (tracker != null) {
      final reconciliation = await SignedOutSyncReconciliationService(
        repository: repository,
        rootDirectory: rootDirectory,
        mutationTracker: tracker,
      ).reconcile(userId: userId, deviceId: deviceId);
      if (reconciliation.queuedMutationCount > 0) {
        final catchUp = await pushService.push(
          userId: userId,
          deviceId: deviceId,
        );
        uploadedOperationCount += catchUp.uploadedOperationCount;
        preservedConflictCount += catchUp.preservedConflictCount;
        preservedDeleteEditCount += catchUp.preservedDeleteEditCount;
      }
    }

    final created = await _syncLocalOnlyRoots(
      userId: userId,
      deviceId: deviceId,
    );
    final createdPages = await _syncLocalOnlyPages(
      userId: userId,
      deviceId: deviceId,
    );
    if (created.uploadedRootCount == 0 && createdPages.pageCount == 0) {
      return IncrementalSyncPushResult(
        uploadedOperationCount: uploadedOperationCount,
        preservedConflictCount:
            preservedConflictCount + created.preservedConflictCount,
        preservedDeleteEditCount: preservedDeleteEditCount,
      );
    }

    await _queueLatestCreatedContent(
      notebookIds: {...created.notebookIds, ...createdPages.notebookIds},
      folderIds: created.folderIds,
    );
    final followUp = await pushService.push(userId: userId, deviceId: deviceId);
    return IncrementalSyncPushResult(
      uploadedOperationCount:
          uploadedOperationCount +
          created.uploadedRootCount +
          createdPages.pageCount +
          followUp.uploadedOperationCount,
      preservedConflictCount:
          preservedConflictCount +
          created.preservedConflictCount +
          followUp.preservedConflictCount,
      preservedDeleteEditCount:
          preservedDeleteEditCount + followUp.preservedDeleteEditCount,
    );
  }

  Future<_LocalChildPageSyncResult> _syncLocalOnlyPages({
    required String userId,
    required String deviceId,
  }) async {
    final bootstrap = await apiClient.bootstrap();
    final folders = await repository.listFolders();
    final notebooks = <Notebook>[
      ...await repository.listNotebooks(),
      for (final folder in folders)
        ...await repository.listNotebooks(folderId: folder.id),
      ...await repository.listNotebooks(archived: true),
    ];
    final cloudNotebooks = {
      for (final notebook in bootstrap.notebooks) notebook.id: notebook,
    };
    final cloudPageIds = {for (final page in bootstrap.pages) page.id};
    final cloudPageCounts = <String, int>{};
    for (final page in bootstrap.pages) {
      cloudPageCounts.update(
        page.notebookId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final missing = <_LocalChildPage>[];
    for (final notebook in notebooks) {
      if (notebook.layoutMode != NotebookLayoutMode.paged ||
          cloudNotebooks[notebook.id]?.layoutMode != 'paged') {
        continue;
      }
      var appendPosition = cloudPageCounts[notebook.id] ?? 0;
      for (final pageId in notebook.pageIds) {
        final remoteId = cloudPageIds.contains(pageId)
            ? pageId
            : remotePageSyncId(notebook.id, pageId);
        if (cloudPageIds.contains(remoteId)) continue;
        missing.add(
          _LocalChildPage(
            notebook: notebook,
            pageId: pageId,
            remoteId: remoteId,
            appendPosition: appendPosition++,
          ),
        );
      }
    }
    if (missing.isEmpty) return const _LocalChildPageSyncResult();

    final snapshot = await _buildLocalChildPageSnapshot(missing);
    await _uploadSnapshot(
      snapshot,
      deviceId: deviceId,
      baseCursor: bootstrap.baseCursor,
    );
    final completed = await apiClient.bootstrap();
    final completedPages = {for (final page in completed.pages) page.id: page};
    for (final page in missing) {
      final cloud = completedPages[page.remoteId];
      if (cloud == null || cloud.notebookId != page.notebook.id) {
        throw StateError('Cloud bootstrap does not contain the uploaded page.');
      }
    }
    _verifyUploadedSnapshot(snapshot, completed);
    await _replaceResourceMappings(
      bootstrap: completed,
      userId: userId,
      deviceId: deviceId,
    );
    return _LocalChildPageSyncResult(
      notebookIds: missing.map((page) => page.notebook.id).toSet(),
      pageCount: missing.length,
    );
  }

  Future<_LocalUploadSnapshot> _buildLocalChildPageSnapshot(
    List<_LocalChildPage> pages,
  ) async {
    final operations = <Map<String, Object?>>[];
    final assetsByPath = <String, LocalSyncAsset>{};
    for (final child in pages) {
      final page = await repository.loadPage(child.notebook, child.pageId);
      final content = Map<String, Object?>.from(page.toJson());
      for (final key in const {
        'id',
        'width',
        'height',
        'coordinateSpaceVersion',
        'rotationQuarterTurns',
        'template',
      }) {
        content.remove(key);
      }
      operations.add(
        _operation('page', child.remoteId, {
          'notebookId': child.notebook.id,
          'position': child.appendPosition,
          'width': page.width,
          'height': page.height,
          'coordinateSpaceVersion': page.persistedCoordinateSpaceVersion,
          'rotationQuarterTurns': page.rotationQuarterTurns,
          'template': page.template.name,
          'content': content,
        }),
      );
      final background = page.pdfBackground;
      if (background != null) {
        await _addAsset(
          assetsByPath,
          child.notebook,
          background.assetPath,
          File(background.filePath),
          'pdf',
        );
      }
      for (final image in page.images) {
        await _addAsset(
          assetsByPath,
          child.notebook,
          image.assetPath,
          File(image.filePath),
          'image',
        );
      }
    }
    return _LocalUploadSnapshot(
      operations: operations,
      assets: assetsByPath.values.toList()
        ..sort((left, right) => left.id.compareTo(right.id)),
      folderIds: const {},
      notebookIds: pages.map((page) => page.notebook.id).toSet(),
    );
  }

  Future<_LocalRootSyncResult> _syncLocalOnlyRoots({
    required String userId,
    required String deviceId,
  }) async {
    final preview = await inspect();
    final assessment = preview.assessment;
    final folderIds = assessment.localOnlyFolderIds;
    final notebookIds = assessment.localOnlyNotebookIds;
    if (folderIds.isEmpty && notebookIds.isEmpty) {
      return const _LocalRootSyncResult();
    }

    var preservedConflictCount = 0;
    if (preview.canUploadLocalOnly) {
      await uploadLocalOnly(
        preview: preview,
        userId: userId,
        deviceId: deviceId,
      );
    } else if (preview.canMergeMixed) {
      final result = await mergeMixed(
        preview: preview,
        userId: userId,
        deviceId: deviceId,
      );
      preservedConflictCount = result.preservedConflictCount;
    } else {
      return const _LocalRootSyncResult();
    }
    return _LocalRootSyncResult(
      folderIds: folderIds,
      notebookIds: notebookIds,
      preservedConflictCount: preservedConflictCount,
    );
  }

  Future<void> _queueLatestCreatedContent({
    required Set<String> notebookIds,
    required Set<String> folderIds,
  }) async {
    final tracker = mutationTracker;
    if (tracker == null) return;
    final folders = await repository.listFolders();
    for (final folder in folders) {
      if (folderIds.contains(folder.id)) {
        await tracker.folderSaved(folder);
      }
    }
    final notebooks = <String, Notebook>{
      for (final notebook in await repository.listNotebooks())
        notebook.id: notebook,
      for (final folder in folders)
        for (final notebook in await repository.listNotebooks(
          folderId: folder.id,
        ))
          notebook.id: notebook,
      for (final notebook in await repository.listNotebooks(archived: true))
        notebook.id: notebook,
    };
    for (final notebookId in notebookIds) {
      final notebook = notebooks[notebookId];
      if (notebook == null) continue;
      await tracker.notebookMetadataSaved(notebook);
      await tracker.notebookContentSaved(notebook);
      if (notebook.layoutMode == NotebookLayoutMode.paged) {
        for (final pageId in notebook.pageIds) {
          await tracker.pageSaved(
            notebook,
            await repository.loadPage(notebook, pageId),
          );
        }
      } else {
        await tracker.infiniteCanvasSaved(
          notebook,
          await repository.loadInfiniteCanvas(notebook),
        );
      }
    }
  }

  @override
  Future<IncrementalSyncPullResult> pullIncremental({
    required String userId,
    required String deviceId,
  }) {
    return IncrementalSyncPullService(
      repository: repository,
      cloudClient: apiClient,
      rootDirectory: rootDirectory,
      mutationTracker: mutationTracker,
    ).pull(userId: userId, deviceId: deviceId);
  }

  @override
  Future<SyncConflictResolutionResult> resolveConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncConflictResolution resolution,
  }) {
    final conflictClient = apiClient;
    if (conflictClient is! SyncConflictCloudClient) {
      throw StateError('The cloud client cannot resolve sync conflicts.');
    }
    return ApiSyncConflictResolutionService(
      cloudClient: conflictClient as SyncConflictCloudClient,
      pullService: IncrementalSyncPullService(
        repository: repository,
        cloudClient: apiClient,
        rootDirectory: rootDirectory,
        mutationTracker: mutationTracker,
      ),
    ).resolveConflict(
      userId: userId,
      deviceId: deviceId,
      conflictId: conflictId,
      resolution: resolution,
    );
  }

  @override
  Future<SyncTombstoneRestoreResult> restoreTombstone({
    required String userId,
    required String deviceId,
    required String tombstoneId,
  }) {
    final tombstoneClient = apiClient;
    if (tombstoneClient is! SyncTombstoneCloudClient) {
      throw StateError('The cloud client cannot restore Tombstones.');
    }
    return ApiSyncTombstoneRestoreService(
      cloudClient: tombstoneClient as SyncTombstoneCloudClient,
      pullService: IncrementalSyncPullService(
        repository: repository,
        cloudClient: apiClient,
        rootDirectory: rootDirectory,
        mutationTracker: mutationTracker,
      ),
    ).restoreTombstone(
      userId: userId,
      deviceId: deviceId,
      tombstoneId: tombstoneId,
    );
  }

  @override
  Future<List<SyncStructuralConflict>> loadStructuralConflicts({
    required String userId,
    required String deviceId,
  }) => FileSyncStructuralConflictStore(
    rootDirectory: rootDirectory,
    userId: userId,
    deviceId: deviceId,
  ).load();

  @override
  Future<SyncStructuralConflictResolutionResult> resolveStructuralConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncStructuralConflictResolution resolution,
  }) async {
    final store = FileSyncStructuralConflictStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    final matching = (await store.load()).where(
      (conflict) => conflict.id == conflictId,
    );
    if (matching.length != 1) {
      throw StateError('The structural conflict is no longer pending.');
    }
    final conflict = matching.single;
    final stateStore = FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    await stateStore.requeueStructuralConflict(
      resourceKey: conflict.id,
      cloudRevision: conflict.cloudRevision,
      cloudMetadata: conflict.cloudMetadata,
      keepLocalMetadata:
          resolution == SyncStructuralConflictResolution.useLocal,
    );
    await store.remove(conflict.id);
    try {
      await pushIncremental(userId: userId, deviceId: deviceId);
      final pull = await pullIncremental(userId: userId, deviceId: deviceId);
      if (pull.status == IncrementalSyncPullStatus.requiresReconciliation ||
          pull.status == IncrementalSyncPullStatus.notInitialized) {
        throw StateError('Structural conflict resolution is not yet applied.');
      }
    } on Object {
      if ((await store.load()).every((item) => item.id != conflict.id)) {
        await store.put(conflict);
      }
      rethrow;
    }
    return SyncStructuralConflictResolutionResult(
      pendingConflicts: await store.load(),
    );
  }

  @override
  Future<FirstSignInSyncPreview> inspect() async {
    final results = await Future.wait<Object>([
      readLocalSyncLibraryInventory(repository),
      apiClient.bootstrap(),
    ]);
    final local = results[0] as SyncLibraryInventory;
    final bootstrap = results[1] as CloudSyncBootstrap;
    final assessment = SyncBootstrapAssessment(
      local: local,
      cloud: bootstrap.inventory,
    );
    return FirstSignInSyncPreview(
      bootstrap: bootstrap,
      assessment: assessment,
      plan: SyncMergePlan.fromAssessment(assessment),
    );
  }

  @override
  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    if (!preview.canRestoreCloudOnly) {
      throw StateError(
        'Only a cloud-only library can use the completed restore path.',
      );
    }
    return withSyncRestoreSnapshot(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
      action: () async {
        final result =
            await BootstrapRestoreService(
              rootDirectory: rootDirectory,
              assetClient: apiClient,
              syncStateStore: FileSyncStateStore(
                rootDirectory: rootDirectory,
                userId: userId,
                deviceId: deviceId,
              ),
            ).downloadAndApplyCloudOnly(
              bootstrap: preview.bootstrap,
              assessment: preview.assessment,
              persistCursor: false,
            );
        await _replaceResourceMappings(
          bootstrap: preview.bootstrap,
          userId: userId,
          deviceId: deviceId,
        );
        await FileSyncStateStore(
          rootDirectory: rootDirectory,
          userId: userId,
          deviceId: deviceId,
        ).markChangesPageApplied(preview.bootstrap.baseCursor);
        return BootstrapRestoreResult(
          downloadedNotebookCount: result.downloadedNotebookCount,
          downloadedAssetCount: result.downloadedAssetCount,
          cursorPersisted: true,
        );
      },
    );
  }

  @override
  Future<LocalMergeUploadResult> uploadLocalOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    if (!preview.canUploadLocalOnly) {
      throw StateError(
        'Only a local-only library can use the completed upload path.',
      );
    }
    final snapshot = await _buildLocalSnapshot(
      folderIds: preview.assessment.localOnlyFolderIds,
      notebookIds: preview.assessment.localOnlyNotebookIds,
    );
    await _uploadSnapshot(
      snapshot,
      deviceId: deviceId,
      baseCursor: preview.bootstrap.baseCursor,
    );

    final completed = await apiClient.bootstrap();
    _verifyUploadedSnapshot(snapshot, completed);
    await _replaceResourceMappings(
      bootstrap: completed,
      userId: userId,
      deviceId: deviceId,
    );
    await FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    ).markChangesPageApplied(completed.baseCursor);
    return LocalMergeUploadResult(
      uploadedNotebookCount: snapshot.notebookCount,
      uploadedAssetCount: snapshot.assets.length,
    );
  }

  @override
  Future<MixedLibraryMergeResult> mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    if (!preview.canMergeMixed) {
      throw StateError('Only a mixed library can use the mixed Merge path.');
    }
    return withSyncRestoreSnapshot(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
      action: () =>
          _mergeMixed(preview: preview, userId: userId, deviceId: deviceId),
    );
  }

  Future<MixedLibraryMergeResult> _mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    final shared = await _buildLocalSnapshot(
      folderIds: preview.assessment.sharedFolderIds,
      notebookIds: preview.assessment.sharedNotebookIds,
      identityBootstrap: preview.bootstrap,
    );
    final localOnly = await _buildLocalSnapshot(
      folderIds: preview.assessment.localOnlyFolderIds,
      notebookIds: preview.assessment.localOnlyNotebookIds,
    );
    _verifySharedStructure(shared, preview.bootstrap);

    var cursor = preview.bootstrap.baseCursor;
    var preservedConflicts = 0;
    final pendingConflicts = <CloudSyncConflict>[];
    final contentOperations = _sharedContentOperations(shared);
    for (var offset = 0; offset < contentOperations.length; offset += 100) {
      final end = (offset + 100).clamp(0, contentOperations.length);
      final operations = contentOperations.sublist(offset, end);
      final fingerprint = _requestFingerprint(cursor, operations);
      final result = await apiClient.commitSharedContent(
        deviceId: deviceId,
        idempotencyKey: 'reconcile-${fingerprint.substring(0, 40)}',
        baseCursor: cursor,
        operations: operations,
      );
      _verifyContentCommit(operations, result);
      preservedConflicts += result.results
          .where((item) => item.outcome == 'conflict')
          .length;
      pendingConflicts.addAll(
        result.results
            .map((item) => item.conflict)
            .whereType<CloudSyncConflict>(),
      );
      cursor = result.nextCursor;
    }
    await _uploadSnapshot(localOnly, deviceId: deviceId, baseCursor: cursor);

    final completed = await apiClient.bootstrap();
    _verifyUploadedSnapshot(localOnly, completed);
    final localBeforeDownload = await readLocalSyncLibraryInventory(repository);
    final completedAssessment = SyncBootstrapAssessment(
      local: localBeforeDownload,
      cloud: completed.inventory,
    );
    final restored =
        await BootstrapRestoreService(
          rootDirectory: rootDirectory,
          assetClient: apiClient,
          syncStateStore: FileSyncStateStore(
            rootDirectory: rootDirectory,
            userId: userId,
            deviceId: deviceId,
          ),
        ).downloadAndApplyCloudOnly(
          bootstrap: completed,
          assessment: completedAssessment,
          persistCursor: false,
        );
    final finalLocal = await readLocalSyncLibraryInventory(repository);
    if (!_sameIds(finalLocal.folderIds, completed.inventory.folderIds) ||
        !_sameIds(finalLocal.notebookIds, completed.inventory.notebookIds)) {
      throw StateError('The completed mixed Merge inventory is incomplete.');
    }
    await _replaceResourceMappings(
      bootstrap: completed,
      userId: userId,
      deviceId: deviceId,
    );
    final conflictStore = FileSyncConflictStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    );
    for (final conflict in pendingConflicts) {
      await conflictStore.applyConflict(conflict);
    }
    await FileSyncStateStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    ).markChangesPageApplied(completed.baseCursor);
    return MixedLibraryMergeResult(
      uploadedNotebookCount: localOnly.notebookCount,
      downloadedNotebookCount: restored.downloadedNotebookCount,
      transferredAssetCount:
          localOnly.assets.length + restored.downloadedAssetCount,
      preservedConflictCount: preservedConflicts,
      pendingConflicts: List.unmodifiable(pendingConflicts),
    );
  }

  Future<void> _replaceResourceMappings({
    required CloudSyncBootstrap bootstrap,
    required String userId,
    required String deviceId,
  }) async {
    final mappings = await buildSyncResourceMappings(
      repository: repository,
      bootstrap: bootstrap,
    );
    await FileSyncResourceMapStore(
      rootDirectory: rootDirectory,
      userId: userId,
      deviceId: deviceId,
    ).replaceAll(mappings, cloudAssetKeys: buildCloudAssetKeys(bootstrap));
  }

  Future<String> _uploadSnapshot(
    _LocalUploadSnapshot snapshot, {
    required String deviceId,
    required String baseCursor,
  }) async {
    var cursor = baseCursor;
    for (var offset = 0; offset < snapshot.operations.length; offset += 100) {
      final end = (offset + 100).clamp(0, snapshot.operations.length);
      final operations = snapshot.operations.sublist(offset, end);
      final fingerprint = _requestFingerprint(cursor, operations);
      final result = await apiClient.commitInitialMerge(
        deviceId: deviceId,
        idempotencyKey: 'bootstrap-${fingerprint.substring(0, 40)}',
        baseCursor: cursor,
        operations: operations,
      );
      cursor = result.nextCursor;
    }

    for (final asset in snapshot.assets) {
      try {
        final session = await apiClient.createAssetUploadSession(asset);
        await apiClient.uploadAssetFile(session, asset);
        await apiClient.completeAssetUpload(session.uploadId);
      } on InkNestApiException catch (error) {
        if (error.code != 'asset_already_exists') rethrow;
      }
    }
    return cursor;
  }

  Future<_LocalUploadSnapshot> _buildLocalSnapshot({
    required Set<String> folderIds,
    required Set<String> notebookIds,
    CloudSyncBootstrap? identityBootstrap,
  }) async {
    final allFolders = await repository.listFolders();
    final allNotebooks = <Notebook>[
      ...await repository.listNotebooks(),
      for (final folder in allFolders)
        ...await repository.listNotebooks(folderId: folder.id),
      ...await repository.listNotebooks(archived: true),
    ];
    final folders =
        allFolders.where((folder) => folderIds.contains(folder.id)).toList()
          ..sort((left, right) => left.id.compareTo(right.id));
    final notebooks =
        allNotebooks
            .where((notebook) => notebookIds.contains(notebook.id))
            .toList()
          ..sort((left, right) => left.id.compareTo(right.id));
    final operations = <Map<String, Object?>>[];
    final assetsByPath = <String, LocalSyncAsset>{};
    final cloudPageIdsByNotebook = <String, Set<String>>{};
    for (final page in identityBootstrap?.pages ?? const <CloudSyncPage>[]) {
      cloudPageIdsByNotebook
          .putIfAbsent(page.notebookId, () => <String>{})
          .add(page.id);
    }

    for (final folder in folders) {
      operations.add(_operation('folder', folder.id, {'name': folder.name}));
    }
    for (final notebook in notebooks) {
      final remotePageIds = {
        for (final pageId in notebook.pageIds)
          pageId: cloudPageIdsByNotebook[notebook.id]?.contains(pageId) ?? false
              ? pageId
              : remotePageSyncId(notebook.id, pageId),
      };
      final notebookJson = Map<String, Object?>.from(
        _rewritePageReferences(notebook.toJson(), remotePageIds) as Map,
      );
      for (final key in const {
        'id',
        'title',
        'createdAt',
        'updatedAt',
        'pageIds',
        'isArchived',
        'folderId',
        'layoutMode',
      }) {
        notebookJson.remove(key);
      }
      operations.add(
        _operation('notebook', notebook.id, {
          if (notebook.folderId != null) 'folderId': notebook.folderId,
          'title': notebook.title,
          'layoutMode': notebook.layoutMode.name,
          'isArchived': notebook.isArchived,
          'content': notebookJson,
        }),
      );

      if (notebook.layoutMode == NotebookLayoutMode.paged) {
        for (final (position, pageId) in notebook.pageIds.indexed) {
          final page = await repository.loadPage(notebook, pageId);
          final content = Map<String, Object?>.from(page.toJson());
          for (final key in const {
            'id',
            'width',
            'height',
            'coordinateSpaceVersion',
            'rotationQuarterTurns',
            'template',
          }) {
            content.remove(key);
          }
          operations.add(
            _operation('page', remotePageIds[page.id]!, {
              'notebookId': notebook.id,
              'position': position,
              'width': page.width,
              'height': page.height,
              'coordinateSpaceVersion': page.persistedCoordinateSpaceVersion,
              'rotationQuarterTurns': page.rotationQuarterTurns,
              'template': page.template.name,
              'content': content,
            }),
          );
          final background = page.pdfBackground;
          if (background != null) {
            await _addAsset(
              assetsByPath,
              notebook,
              background.assetPath,
              File(background.filePath),
              'pdf',
            );
          }
          for (final image in page.images) {
            await _addAsset(
              assetsByPath,
              notebook,
              image.assetPath,
              File(image.filePath),
              'image',
            );
          }
        }
      } else {
        final canvas = await repository.loadInfiniteCanvas(notebook);
        final content = Map<String, Object?>.from(canvas.toJson())
          ..remove('background');
        operations.add(
          _operation('infinite_canvas', _canvasId(notebook.id), {
            'notebookId': notebook.id,
            'background': canvas.background.name,
            'content': content,
          }),
        );
        for (final image in canvas.images) {
          await _addAsset(
            assetsByPath,
            notebook,
            image.assetPath,
            File(image.filePath),
            'image',
          );
        }
      }
      for (final recording in notebook.audioRecordings) {
        await _addAsset(
          assetsByPath,
          notebook,
          recording.assetPath,
          File(recording.filePath),
          'audio',
        );
      }
    }
    return _LocalUploadSnapshot(
      operations: operations,
      assets: assetsByPath.values.toList()
        ..sort((left, right) => left.id.compareTo(right.id)),
      folderIds: folders.map((item) => item.id).toSet(),
      notebookIds: notebooks.map((item) => item.id).toSet(),
    );
  }

  void _verifySharedStructure(
    _LocalUploadSnapshot local,
    CloudSyncBootstrap cloud,
  ) {
    final cloudFolders = {for (final item in cloud.folders) item.id: item};
    final cloudNotebooks = {for (final item in cloud.notebooks) item.id: item};
    final cloudPages = {for (final item in cloud.pages) item.id: item};
    final cloudCanvases = {
      for (final item in cloud.infiniteCanvases) item.id: item,
    };
    final localPages = <String>{};
    final localCanvases = <String>{};

    for (final operation in local.operations) {
      final type = operation['resourceType']! as String;
      final id = operation['resourceId']! as String;
      final metadata = operation['metadata']! as Map<String, Object?>;
      switch (type) {
        case 'folder':
          final remote = cloudFolders[id];
          if (remote == null || remote.name != metadata['name']) {
            throw StateError(
              'A shared folder has incompatible local and cloud metadata.',
            );
          }
          break;
        case 'notebook':
          final remote = cloudNotebooks[id];
          if (remote == null ||
              remote.folderId != metadata['folderId'] ||
              remote.title != metadata['title'] ||
              remote.layoutMode != metadata['layoutMode'] ||
              remote.isArchived != metadata['isArchived']) {
            throw StateError(
              'A shared notebook has incompatible structural metadata.',
            );
          }
          break;
        case 'page':
          localPages.add(id);
          final remote = cloudPages[id];
          final mismatchedFields = <String>[
            if (remote == null) 'missingCloudPage',
            if (remote != null && remote.notebookId != metadata['notebookId'])
              'notebookId',
            if (remote != null && remote.position != metadata['position'])
              'position',
            if (remote != null && remote.width != metadata['width']) 'width',
            if (remote != null && remote.height != metadata['height']) 'height',
            if (remote != null &&
                !_jsonEquals(
                  remote.coordinateSpaceVersion,
                  metadata['coordinateSpaceVersion'],
                ))
              'coordinateSpaceVersion',
            if (remote != null &&
                remote.rotationQuarterTurns != metadata['rotationQuarterTurns'])
              'rotationQuarterTurns',
            if (remote != null && remote.template != metadata['template'])
              'template',
          ];
          if (mismatchedFields.isNotEmpty) {
            throw StateError(
              'A shared page has incompatible structural metadata: '
              '${mismatchedFields.join(', ')}.',
            );
          }
          break;
        case 'infinite_canvas':
          localCanvases.add(id);
          final remote = cloudCanvases[id];
          if (remote == null ||
              remote.notebookId != metadata['notebookId'] ||
              remote.background != metadata['background']) {
            throw StateError(
              'A shared canvas has incompatible structural metadata.',
            );
          }
          break;
      }
    }

    final cloudSharedPages = cloud.pages
        .where((item) => local.notebookIds.contains(item.notebookId))
        .map((item) => item.id)
        .toSet();
    final cloudSharedCanvases = cloud.infiniteCanvases
        .where((item) => local.notebookIds.contains(item.notebookId))
        .map((item) => item.id)
        .toSet();
    if (!_sameIds(localPages, cloudSharedPages) ||
        !_sameIds(localCanvases, cloudSharedCanvases)) {
      throw StateError(
        'A shared notebook has different local and cloud child resources.',
      );
    }

    final cloudAssets = {
      for (final item in cloud.assets)
        if (local.notebookIds.contains(item.notebookId)) item.id: item,
    };
    if (cloudAssets.length != local.assets.length) {
      throw StateError(
        'A shared notebook has different local and cloud attachments.',
      );
    }
    for (final asset in local.assets) {
      final remote = cloudAssets[asset.id];
      if (remote == null ||
          remote.notebookId != asset.notebookId ||
          remote.kind != asset.kind ||
          remote.originalFilename != asset.filename ||
          remote.relativePath != asset.relativePath ||
          remote.contentType != asset.contentType ||
          remote.byteSize != asset.byteSize ||
          remote.sha256 != asset.sha256) {
        throw StateError(
          'A shared attachment does not match its verified cloud object.',
        );
      }
    }
  }

  List<Map<String, Object?>> _sharedContentOperations(
    _LocalUploadSnapshot snapshot,
  ) {
    return [
      for (final create in snapshot.operations)
        if (create['resourceType'] != 'folder')
          {
            'operationId': (create['operationId']! as String).replaceFirst(
              'create-',
              'reconcile-',
            ),
            'operation': 'upsert',
            'resourceType': create['resourceType'],
            'resourceId': create['resourceId'],
            'baseRevision': 0,
            'content': (create['metadata']! as Map<String, Object?>)['content'],
          },
    ];
  }

  void _verifyContentCommit(
    List<Map<String, Object?>> operations,
    SyncContentCommitResult result,
  ) {
    if (result.results.length != operations.length) {
      throw const FormatException(
        'Shared-content commit returned an incomplete result set.',
      );
    }
    final expected = {
      for (final item in operations)
        item['operationId']! as String:
            '${item['resourceType']}:${item['resourceId']}',
    };
    for (final item in result.results) {
      if (expected[item.operationId] !=
          '${item.resourceType}:${item.resourceId}') {
        throw const FormatException(
          'Shared-content commit returned a mismatched operation result.',
        );
      }
    }
  }

  String _requestFingerprint(
    String cursor,
    List<Map<String, Object?>> operations,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode({'baseCursor': cursor, 'operations': operations}),
        ),
      )
      .toString();

  bool _sameIds(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool _jsonEquals(Object? left, Object? right) {
    if (left is List<Object?> && right is List<Object?>) {
      return left.length == right.length &&
          left.indexed.every((entry) => _jsonEquals(entry.$2, right[entry.$1]));
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.entries.every(
            (entry) =>
                right.containsKey(entry.key) &&
                _jsonEquals(entry.value, right[entry.key]),
          );
    }
    return left == right;
  }

  Map<String, Object?> _operation(
    String resourceType,
    String resourceId,
    Map<String, Object?> metadata,
  ) {
    final suffix = sha256
        .convert(utf8.encode('$resourceType\u0000$resourceId'))
        .toString()
        .substring(0, 20);
    return {
      'operationId': 'create-$suffix',
      'resourceType': resourceType,
      'resourceId': resourceId,
      'metadata': metadata,
    };
  }

  Future<void> _addAsset(
    Map<String, LocalSyncAsset> assets,
    Notebook notebook,
    String relativePath,
    File file,
    String kind,
  ) async {
    final key = '${notebook.id}:$relativePath';
    if (assets.containsKey(key)) return;
    assets[key] = await createLocalSyncAsset(
      notebook: notebook,
      relativePath: relativePath,
      file: file,
      kind: kind,
    );
  }

  void _verifyUploadedSnapshot(
    _LocalUploadSnapshot local,
    CloudSyncBootstrap cloud,
  ) {
    if (!cloud.inventory.folderIds.containsAll(local.folderIds) ||
        !cloud.inventory.notebookIds.containsAll(local.notebookIds)) {
      throw StateError(
        'Cloud bootstrap does not contain the uploaded library.',
      );
    }
    final assets = {for (final asset in cloud.assets) asset.id: asset};
    for (final localAsset in local.assets) {
      final cloudAsset = assets[localAsset.id];
      if (cloudAsset == null ||
          cloudAsset.notebookId != localAsset.notebookId ||
          cloudAsset.relativePath != localAsset.relativePath ||
          cloudAsset.byteSize != localAsset.byteSize ||
          cloudAsset.sha256 != localAsset.sha256) {
        throw StateError('Cloud attachment verification failed.');
      }
    }
  }

  String _canvasId(String notebookId) =>
      'canvas-${sha256.convert(utf8.encode(notebookId)).toString().substring(0, 40)}';

  Object? _rewritePageReferences(
    Object? value,
    Map<String, String> remotePageIds, {
    String? key,
  }) {
    if (key == 'pageId' && value is String) {
      return remotePageIds[value] ?? value;
    }
    if (key == 'bookmarkedPageIds' && value is List<Object?>) {
      return [
        for (final pageId in value)
          if (pageId is String) remotePageIds[pageId] ?? pageId,
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _rewritePageReferences(
            entry.value,
            remotePageIds,
            key: entry.key as String,
          ),
      };
    }
    if (value is List<Object?>) {
      return [
        for (final item in value) _rewritePageReferences(item, remotePageIds),
      ];
    }
    return value;
  }
}

class _LocalRootSyncResult {
  const _LocalRootSyncResult({
    this.folderIds = const <String>{},
    this.notebookIds = const <String>{},
    this.preservedConflictCount = 0,
  });

  final Set<String> folderIds;
  final Set<String> notebookIds;
  final int preservedConflictCount;
  int get uploadedRootCount => folderIds.length + notebookIds.length;
}

class _LocalChildPageSyncResult {
  const _LocalChildPageSyncResult({
    this.notebookIds = const <String>{},
    this.pageCount = 0,
  });

  final Set<String> notebookIds;
  final int pageCount;
}

class _LocalChildPage {
  const _LocalChildPage({
    required this.notebook,
    required this.pageId,
    required this.remoteId,
    required this.appendPosition,
  });

  final Notebook notebook;
  final String pageId;
  final String remoteId;
  final int appendPosition;
}

class _LocalUploadSnapshot {
  const _LocalUploadSnapshot({
    required this.operations,
    required this.assets,
    required this.folderIds,
    required this.notebookIds,
  });

  final List<Map<String, Object?>> operations;
  final List<LocalSyncAsset> assets;
  final Set<String> folderIds;
  final Set<String> notebookIds;
  int get notebookCount => notebookIds.length;
}
