import 'dart:io';

import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

abstract interface class CloudAssetTransferClient {
  Future<CloudAssetDownload> createAssetDownload(String assetId);

  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  );
}

abstract interface class FirstSignInCloudClient
    implements CloudAssetTransferClient {
  Future<CloudSyncBootstrap> bootstrap();

  Future<CloudSyncChangePage> listChanges({String? cursor, int limit = 100});

  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  });

  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  });

  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  );

  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  );

  Future<void> completeAssetUpload(String uploadId);
}
