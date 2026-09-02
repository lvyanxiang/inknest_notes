import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/automatic_first_sign_in_sync.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';

void main() {
  test('cloud-only first sign-in restores automatically', () async {
    final service = _AutomaticSyncService(
      preview: _preview(
        local: SyncLibraryInventory(),
        cloud: SyncLibraryInventory(notebookIds: const ['cloud-notebook']),
      ),
    );

    final result = await runAutomaticFirstSignInSync(
      service: service,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(service.executedPath, 'restore');
    expect(result.changedLocalLibrary, isTrue);
    expect(result.restoreResult?.downloadedNotebookCount, 1);
  });

  test('local-only first sign-in uploads automatically', () async {
    final service = _AutomaticSyncService(
      preview: _preview(
        local: SyncLibraryInventory(notebookIds: const ['local-notebook']),
        cloud: SyncLibraryInventory(),
      ),
    );

    final result = await runAutomaticFirstSignInSync(
      service: service,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(service.executedPath, 'upload');
    expect(result.changedLocalLibrary, isFalse);
    expect(result.uploadResult?.uploadedNotebookCount, 1);
  });

  test('mixed first sign-in preserves and exposes conflicts', () async {
    final conflict = _conflict();
    final service = _AutomaticSyncService(
      preview: _preview(
        local: SyncLibraryInventory(notebookIds: const ['shared-notebook']),
        cloud: SyncLibraryInventory(notebookIds: const ['shared-notebook']),
      ),
      pendingConflicts: [conflict],
    );

    final result = await runAutomaticFirstSignInSync(
      service: service,
      userId: 'user-1',
      deviceId: 'device-1',
    );

    expect(service.executedPath, 'merge');
    expect(result.pendingConflicts.single.id, conflict.id);
  });
}

class _AutomaticSyncService implements FirstSignInSyncService {
  _AutomaticSyncService({
    required this.preview,
    this.pendingConflicts = const [],
  });

  final FirstSignInSyncPreview preview;
  final List<CloudSyncConflict> pendingConflicts;
  String? executedPath;

  @override
  Future<FirstSignInSyncPreview> inspect() async => preview;

  @override
  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    executedPath = 'restore';
    return const BootstrapRestoreResult(
      downloadedNotebookCount: 1,
      downloadedAssetCount: 2,
      cursorPersisted: true,
    );
  }

  @override
  Future<LocalMergeUploadResult> uploadLocalOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    executedPath = 'upload';
    return const LocalMergeUploadResult(
      uploadedNotebookCount: 1,
      uploadedAssetCount: 2,
    );
  }

  @override
  Future<MixedLibraryMergeResult> mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    executedPath = 'merge';
    return MixedLibraryMergeResult(
      uploadedNotebookCount: 0,
      downloadedNotebookCount: 0,
      transferredAssetCount: 0,
      preservedConflictCount: pendingConflicts.length,
      pendingConflicts: pendingConflicts,
    );
  }

  @override
  Future<IncrementalSyncPullResult> pullIncremental({
    required String userId,
    required String deviceId,
  }) => throw UnimplementedError();

  @override
  Future<IncrementalSyncPushResult> pushIncremental({
    required String userId,
    required String deviceId,
  }) => throw UnimplementedError();
}

FirstSignInSyncPreview _preview({
  required SyncLibraryInventory local,
  required SyncLibraryInventory cloud,
}) {
  final assessment = SyncBootstrapAssessment(local: local, cloud: cloud);
  return FirstSignInSyncPreview(
    bootstrap: CloudSyncBootstrap(
      inventory: cloud,
      baseCursor: 'cursor-1',
      folders: const [],
      notebooks: const [],
      pages: const [],
      infiniteCanvases: const [],
      assets: const [],
    ),
    assessment: assessment,
    plan: SyncMergePlan.fromAssessment(assessment),
  );
}

CloudSyncConflict _conflict() => CloudSyncConflict(
  id: 'conflict-1',
  resourceType: 'page',
  originalResourceId: 'page-1',
  copyResourceId: 'page-copy-1',
  copyDisplayName: '第 1 页（冲突副本）',
  baseRevision: 1,
  currentRevision: 2,
  submittedContentHash: 'a' * 64,
  submittedContent: const {'strokes': <Object?>[]},
  currentContentHash: 'b' * 64,
  currentContent: const {'strokes': <Object?>[]},
  sourceDeviceId: 'device-2',
  status: 'pending',
  resolution: null,
  resolvedByDeviceId: null,
  resolvedAt: null,
  createdAt: DateTime.utc(2026, 8, 31),
);
