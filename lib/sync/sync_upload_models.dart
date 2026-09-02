import 'dart:io';

import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

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

class SyncContentCommitOperationResult {
  const SyncContentCommitOperationResult({
    required this.operationId,
    required this.resourceType,
    required this.resourceId,
    required this.revision,
    required this.contentHash,
    required this.outcome,
    this.conflict,
  });

  final String operationId;
  final String resourceType;
  final String resourceId;
  final int revision;
  final String contentHash;
  final String outcome;
  final CloudSyncConflict? conflict;

  factory SyncContentCommitOperationResult.fromJson(Map<String, Object?> json) {
    final resourceType = requiredString(json, 'resourceType');
    final revision = json['revision'];
    final outcome = requiredString(json, 'outcome');
    final rawConflict = json['conflict'];
    if (!const {
          'folder',
          'notebook',
          'page',
          'infinite_canvas',
        }.contains(resourceType) ||
        revision is! int ||
        revision < 0 ||
        !const {
          'applied',
          'unchanged',
          'conflict',
          'deleted',
          'delete_conflict',
        }.contains(outcome)) {
      throw const FormatException('Invalid shared-content commit result.');
    }
    final conflict = rawConflict == null
        ? null
        : rawConflict is Map<Object?, Object?>
        ? CloudSyncConflict.fromJson(rawConflict.cast<String, Object?>())
        : throw const FormatException(
            'Invalid shared-content conflict result.',
          );
    if ((outcome == 'conflict') != (conflict != null)) {
      throw const FormatException(
        'Shared-content conflict outcome does not match its payload.',
      );
    }
    final resourceId = requiredString(json, 'resourceId');
    if (conflict != null && conflict.originalResourceId != resourceId) {
      throw const FormatException(
        'Shared-content conflict resource does not match its operation.',
      );
    }
    return SyncContentCommitOperationResult(
      operationId: requiredString(json, 'operationId'),
      resourceType: resourceType,
      resourceId: resourceId,
      revision: revision,
      contentHash: requiredSha256(json, 'contentHash'),
      outcome: outcome,
      conflict: conflict,
    );
  }
}

class SyncContentCommitResult {
  SyncContentCommitResult({
    required this.idempotencyKey,
    required this.nextCursor,
    required List<SyncContentCommitOperationResult> results,
  }) : results = List.unmodifiable(results);

  final String idempotencyKey;
  final String nextCursor;
  final List<SyncContentCommitOperationResult> results;

  factory SyncContentCommitResult.fromJson(Map<String, Object?> json) {
    final rawResults = json['results'];
    if (rawResults is! List<Object?> ||
        rawResults.any((item) => item is! Map<Object?, Object?>)) {
      throw const FormatException('Invalid shared-content commit response.');
    }
    final results = rawResults
        .map(
          (item) => SyncContentCommitOperationResult.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
    if (results.map((item) => item.operationId).toSet().length !=
        results.length) {
      throw const FormatException(
        'Shared-content commit results contain duplicate operations.',
      );
    }
    return SyncContentCommitResult(
      idempotencyKey: requiredString(json, 'idempotencyKey'),
      nextCursor: requiredString(json, 'nextCursor'),
      results: results,
    );
  }
}
