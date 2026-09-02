import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

class AutomaticFirstSignInSyncResult {
  const AutomaticFirstSignInSyncResult({
    this.restoreResult,
    this.uploadResult,
    this.mixedResult,
  });

  final BootstrapRestoreResult? restoreResult;
  final LocalMergeUploadResult? uploadResult;
  final MixedLibraryMergeResult? mixedResult;

  bool get changedLocalLibrary => restoreResult != null || mixedResult != null;

  List<CloudSyncConflict> get pendingConflicts =>
      mixedResult?.pendingConflicts ?? const [];
}

Future<AutomaticFirstSignInSyncResult> runAutomaticFirstSignInSync({
  required FirstSignInSyncService service,
  required String userId,
  required String deviceId,
}) async {
  final preview = await service.inspect();
  return switch (preview.assessment.presence) {
    SyncLibraryPresence.empty => const AutomaticFirstSignInSyncResult(),
    SyncLibraryPresence.cloudOnly => AutomaticFirstSignInSyncResult(
      restoreResult: await service.restoreCloudOnly(
        preview: preview,
        userId: userId,
        deviceId: deviceId,
      ),
    ),
    SyncLibraryPresence.localOnly => AutomaticFirstSignInSyncResult(
      uploadResult: await service.uploadLocalOnly(
        preview: preview,
        userId: userId,
        deviceId: deviceId,
      ),
    ),
    SyncLibraryPresence.localAndCloud => AutomaticFirstSignInSyncResult(
      mixedResult: await service.mergeMixed(
        preview: preview,
        userId: userId,
        deviceId: deviceId,
      ),
    ),
  };
}
