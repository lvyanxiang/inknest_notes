import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

void main() {
  test(
    'local-only merge uploads structure, page content, and image bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-local-upload-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = FileNotebookRepository(rootDirectory: root);
      final notebook = await repository.createNotebook(title: 'Local notes');
      final secondNotebook = await repository.createNotebook(
        title: 'Other local notes',
      );
      final source = File('${root.path}/source.png')
        ..writeAsBytesSync(const [1, 2, 3, 4]);
      final image = await repository.importImage(
        notebook,
        source,
        position: const Offset(20, 30),
        width: 100,
        height: 80,
      );
      await repository.savePage(
        notebook,
        NotePage(
          id: notebook.pageIds.single,
          width: 768,
          height: 1024,
          images: [image],
        ),
      );
      await repository.setPageBookmarked(
        notebook,
        notebook.pageIds.single,
        true,
      );
      final cloud = _FakeFirstSignInCloudClient();
      final service = ApiFirstSignInSyncService(
        repository: repository,
        apiClient: cloud,
        rootDirectory: root,
      );

      final preview = await service.inspect();
      final result = await service.uploadLocalOnly(
        preview: preview,
        userId: 'user-1',
        deviceId: 'device-1',
      );

      expect(result.uploadedNotebookCount, 2);
      expect(result.uploadedAssetCount, 1);
      expect(
        cloud.operations.map((item) => item['resourceType']),
        containsAllInOrder(['notebook', 'page', 'notebook', 'page']),
      );
      final pageOperations = cloud.operations
          .where((item) => item['resourceType'] == 'page')
          .toList();
      expect(pageOperations, hasLength(2));
      expect(
        pageOperations.map((item) => item['resourceId']).toSet(),
        hasLength(2),
      );
      expect(
        pageOperations.map((item) => item['resourceId']),
        isNot(contains('page-1')),
      );
      expect(secondNotebook.pageIds.single, 'page-1');
      final notebookOperation = cloud.operations.firstWhere(
        (item) =>
            item['resourceType'] == 'notebook' &&
            item['resourceId'] == notebook.id,
      );
      final notebookContent =
          (notebookOperation['metadata']! as Map<String, Object?>)['content']!
              as Map<String, Object?>;
      expect(notebookContent['bookmarkedPageIds'], [
        pageOperations.firstWhere(
          (item) =>
              (item['metadata']! as Map<String, Object?>)['notebookId'] ==
              notebook.id,
        )['resourceId'],
      ]);
      expect(cloud.uploadedAsset?.relativePath, image.assetPath);
      expect(cloud.uploadedAsset?.sha256, hasLength(64));
      final state = await FileSyncStateStore(
        rootDirectory: root,
        userId: 'user-1',
        deviceId: 'device-1',
      ).loadSnapshot();
      expect(state.lastAppliedCursor, 'cursor-complete');
    },
  );
}

class _FakeFirstSignInCloudClient implements FirstSignInCloudClient {
  final operations = <Map<String, Object?>>[];
  LocalSyncAsset? uploadedAsset;
  bool _completed = false;

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    final asset = uploadedAsset;
    return CloudSyncBootstrap(
      inventory: SyncLibraryInventory(
        notebookIds: _completed ? _notebookIds.toList() : const [],
      ),
      baseCursor: _completed ? 'cursor-complete' : 'cursor-empty',
      folders: const [],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: _completed && asset != null
          ? [
              CloudSyncAsset(
                id: asset.id,
                notebookId: asset.notebookId,
                kind: asset.kind,
                originalFilename: asset.filename,
                relativePath: asset.relativePath,
                contentType: asset.contentType,
                byteSize: asset.byteSize,
                sha256: asset.sha256,
                createdAt: DateTime.utc(2026, 8, 6),
                updatedAt: DateTime.utc(2026, 8, 6),
              ),
            ]
          : const [],
    );
  }

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    this.operations.addAll(operations);
    _notebookIds.addAll(
      operations
          .where((item) => item['resourceType'] == 'notebook')
          .map((item) => item['resourceId']! as String),
    );
    return const SyncMergeCommitResult(nextCursor: 'cursor-merged');
  }

  final Set<String> _notebookIds = {};

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) async {
    uploadedAsset = asset;
    return CloudAssetUploadSession(
      uploadId: 'upload-1',
      assetId: asset.id,
      uploadUrl: Uri.parse('https://objects.example.com/upload'),
      requiredHeaders: const {'Content-Type': 'image/png'},
    );
  }

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) async {
    expect(await asset.file.readAsBytes(), const [1, 2, 3, 4]);
  }

  @override
  Future<void> completeAssetUpload(String uploadId) async {
    expect(uploadId, 'upload-1');
    _completed = true;
  }

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) =>
      throw UnimplementedError();

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) => throw UnimplementedError();
}
