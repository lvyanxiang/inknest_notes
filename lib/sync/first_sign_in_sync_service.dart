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
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_restore_snapshot.dart';
import 'package:inknest_notes/sync/sync_tombstone_restore_service.dart';
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
  });

  final int uploadedNotebookCount;
  final int downloadedNotebookCount;
  final int transferredAssetCount;
  final int preservedConflictCount;
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
        SyncTombstoneRestoreService {
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
  }) {
    return IncrementalSyncPushService(
      cloudClient: apiClient,
      rootDirectory: rootDirectory,
    ).push(userId: userId, deviceId: deviceId);
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
    );
    final localOnly = await _buildLocalSnapshot(
      folderIds: preview.assessment.localOnlyFolderIds,
      notebookIds: preview.assessment.localOnlyNotebookIds,
    );
    _verifySharedStructure(shared, preview.bootstrap);

    var cursor = preview.bootstrap.baseCursor;
    var preservedConflicts = 0;
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

    for (final folder in folders) {
      operations.add(_operation('folder', folder.id, {'name': folder.name}));
    }
    for (final notebook in notebooks) {
      final remotePageIds = {
        for (final pageId in notebook.pageIds)
          pageId: _remotePageId(notebook.id, pageId),
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
          if (remote == null ||
              remote.notebookId != metadata['notebookId'] ||
              remote.position != metadata['position'] ||
              remote.width != metadata['width'] ||
              remote.height != metadata['height'] ||
              !_jsonEquals(
                remote.coordinateSpaceVersion,
                metadata['coordinateSpaceVersion'],
              ) ||
              remote.rotationQuarterTurns != metadata['rotationQuarterTurns'] ||
              remote.template != metadata['template']) {
            throw StateError(
              'A shared page has incompatible structural metadata.',
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
    validateNotebookAssetPath(relativePath, kind: kind);
    final key = '${notebook.id}:$relativePath';
    if (assets.containsKey(key)) return;
    if (!await file.exists()) {
      throw StateError('A referenced local attachment is missing.');
    }
    final byteSize = await file.length();
    if (byteSize <= 0) {
      throw StateError('A referenced local attachment is empty.');
    }
    final digest = await sha256.bind(file.openRead()).first;
    final filename = relativePath.split('/').last;
    assets[key] = LocalSyncAsset(
      id: _assetId(notebook.id, relativePath),
      notebookId: notebook.id,
      kind: kind,
      filename: filename,
      relativePath: relativePath,
      contentType: _contentType(filename, kind),
      byteSize: byteSize,
      sha256: digest.toString(),
      file: file,
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

  String _assetId(String notebookId, String path) =>
      'asset-${sha256.convert(utf8.encode('$notebookId\u0000$path')).toString().substring(0, 40)}';

  String _remotePageId(String notebookId, String localPageId) =>
      'page-${sha256.convert(utf8.encode('$notebookId\u0000$localPageId')).toString().substring(0, 40)}';

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

  String _contentType(String filename, String kind) {
    final extension = filename.toLowerCase().split('.').last;
    return switch ((kind, extension)) {
      ('pdf', _) => 'application/pdf',
      ('image', 'png') => 'image/png',
      ('image', 'jpg') || ('image', 'jpeg') => 'image/jpeg',
      ('image', 'webp') => 'image/webp',
      ('image', 'heic') => 'image/heic',
      ('image', 'heif') => 'image/heif',
      ('audio', 'm4a') => 'audio/mp4',
      ('audio', 'mp4') => 'audio/mp4',
      ('audio', 'mp3') => 'audio/mpeg',
      ('audio', 'aac') => 'audio/aac',
      ('audio', 'ogg') => 'audio/ogg',
      ('audio', 'webm') => 'audio/webm',
      ('audio', 'wav') => 'audio/wav',
      _ => throw StateError('Unsupported local attachment type.'),
    };
  }
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
