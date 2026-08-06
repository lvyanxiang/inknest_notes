import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';

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
}

abstract interface class FirstSignInSyncService {
  Future<FirstSignInSyncPreview> inspect();

  Future<BootstrapRestoreResult> restoreCloudOnly({
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
  final InkNestApiClient apiClient;
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
}
