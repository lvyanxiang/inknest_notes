import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';

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
}

class LocalMergeUploadResult {
  const LocalMergeUploadResult({
    required this.uploadedNotebookCount,
    required this.uploadedAssetCount,
  });

  final int uploadedNotebookCount;
  final int uploadedAssetCount;
}

abstract interface class FirstSignInSyncService {
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
}

class ApiFirstSignInSyncService implements FirstSignInSyncService {
  const ApiFirstSignInSyncService({
    required this.repository,
    required this.apiClient,
    required this.rootDirectory,
  });

  final NotebookRepository repository;
  final FirstSignInCloudClient apiClient;
  final Directory rootDirectory;

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
  }) {
    if (!preview.canRestoreCloudOnly) {
      throw StateError(
        'Only a cloud-only library can use the completed restore path.',
      );
    }
    return BootstrapRestoreService(
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
    final snapshot = await _buildLocalUploadSnapshot(preview.assessment);
    var cursor = preview.bootstrap.baseCursor;
    for (var offset = 0; offset < snapshot.operations.length; offset += 100) {
      final end = (offset + 100).clamp(0, snapshot.operations.length);
      final operations = snapshot.operations.sublist(offset, end);
      final fingerprint = sha256.convert(
        utf8.encode(
          jsonEncode({'baseCursor': cursor, 'operations': operations}),
        ),
      );
      final result = await apiClient.commitInitialMerge(
        deviceId: deviceId,
        idempotencyKey: 'bootstrap-${fingerprint.toString().substring(0, 40)}',
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

    final completed = await apiClient.bootstrap();
    _verifyUploadedSnapshot(snapshot, completed);
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

  Future<_LocalUploadSnapshot> _buildLocalUploadSnapshot(
    SyncBootstrapAssessment assessment,
  ) async {
    final allFolders = await repository.listFolders();
    final allNotebooks = <Notebook>[
      ...await repository.listNotebooks(),
      for (final folder in allFolders)
        ...await repository.listNotebooks(folderId: folder.id),
      ...await repository.listNotebooks(archived: true),
    ];
    final folders =
        allFolders
            .where(
              (folder) => assessment.localOnlyFolderIds.contains(folder.id),
            )
            .toList()
          ..sort((left, right) => left.id.compareTo(right.id));
    final notebooks =
        allNotebooks
            .where(
              (notebook) =>
                  assessment.localOnlyNotebookIds.contains(notebook.id),
            )
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
