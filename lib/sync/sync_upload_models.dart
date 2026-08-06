import 'dart:io';

import 'package:inknest_notes/sync/inknest_api_models.dart';

class LocalSyncAsset {
  const LocalSyncAsset({
    required this.id,
    required this.notebookId,
    required this.kind,
    required this.filename,
    required this.relativePath,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.file,
  });

  final String id;
  final String notebookId;
  final String kind;
  final String filename;
  final String relativePath;
  final String contentType;
  final int byteSize;
  final String sha256;
  final File file;

  Map<String, Object?> toCreateJson() => {
    'notebookId': notebookId,
    'assetId': id,
    'kind': kind,
    'filename': filename,
    'relativePath': relativePath,
    'contentType': contentType,
    'byteSize': byteSize,
    'sha256': sha256,
  };
}

class CloudAssetUploadSession {
  CloudAssetUploadSession({
    required this.uploadId,
    required this.assetId,
    required this.uploadUrl,
    required Map<String, String> requiredHeaders,
  }) : requiredHeaders = Map.unmodifiable(requiredHeaders);

  final String uploadId;
  final String assetId;
  final Uri uploadUrl;
  final Map<String, String> requiredHeaders;

  factory CloudAssetUploadSession.fromJson(Map<String, Object?> json) {
    final rawUrl = requiredString(json, 'uploadUrl');
    final uploadUrl = Uri.tryParse(rawUrl);
    final method = json['method'];
    final rawHeaders = json['requiredHeaders'];
    if (uploadUrl == null ||
        !uploadUrl.hasAuthority ||
        !const {'http', 'https'}.contains(uploadUrl.scheme) ||
        method != 'PUT' ||
        rawHeaders is! Map<Object?, Object?> ||
        rawHeaders.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        )) {
      throw const FormatException('Invalid asset upload session response.');
    }
    return CloudAssetUploadSession(
      uploadId: requiredString(json, 'uploadId'),
      assetId: requiredString(json, 'assetId'),
      uploadUrl: uploadUrl,
      requiredHeaders: rawHeaders.cast<String, String>(),
    );
  }
}

class SyncMergeCommitResult {
  const SyncMergeCommitResult({required this.nextCursor});

  final String nextCursor;

  factory SyncMergeCommitResult.fromJson(Map<String, Object?> json) {
    final results = json['results'];
    if (results is! List<Object?> ||
        results.any((item) => item is! Map<Object?, Object?>)) {
      throw const FormatException('Invalid Merge commit response.');
    }
    return SyncMergeCommitResult(
      nextCursor: requiredString(json, 'nextCursor'),
    );
  }
}
