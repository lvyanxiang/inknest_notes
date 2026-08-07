import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

void main() {
  testWidgets('signed-in startup pushes before pull and reports upload count', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService();

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull']);
    expect(find.text('已上传 2 项本地更改。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shared pull reports updated existing content', (tester) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pullResult: const IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: 1,
        appliedSharedResourceCount: 1,
      ),
    );

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('更新 1 项已有内容'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _StartupSyncService implements FirstSignInSyncService {
  _StartupSyncService({
    this.uploadedOperationCount = 2,
    this.pullResult = const IncrementalSyncPullResult(
      status: IncrementalSyncPullStatus.upToDate,
    ),
  });

  final int uploadedOperationCount;
  final IncrementalSyncPullResult pullResult;
  final List<String> calls = [];

  @override
  Future<IncrementalSyncPushResult> pushIncremental({
    required String userId,
    required String deviceId,
  }) async {
    calls.add('push');
    return IncrementalSyncPushResult(
      uploadedOperationCount: uploadedOperationCount,
      preservedConflictCount: 0,
    );
  }

  @override
  Future<IncrementalSyncPullResult> pullIncremental({
    required String userId,
    required String deviceId,
  }) async {
    calls.add('pull');
    return pullResult;
  }

  @override
  Future<FirstSignInSyncPreview> inspect() => throw UnimplementedError();

  @override
  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) => throw UnimplementedError();

  @override
  Future<LocalMergeUploadResult> uploadLocalOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) => throw UnimplementedError();

  @override
  Future<MixedLibraryMergeResult> mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) => throw UnimplementedError();
}

class _RestoredAuthService implements AuthService {
  @override
  Future<InkNestAuthSession?> restoreSession() async => _session();

  @override
  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) => throw UnimplementedError();

  @override
  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

InkNestAuthSession _session() {
  final now = DateTime.utc(2026, 8, 7);
  return InkNestAuthSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'bearer',
    expiresIn: 900,
    user: InkNestCloudUser(
      id: 'user-1',
      email: 'writer@example.com',
      createdAt: now,
    ),
    device: InkNestCloudDevice(
      id: 'device-1',
      name: 'Test iPad',
      platform: 'ios',
      createdAt: now,
      lastSeenAt: now,
      current: true,
    ),
  );
}
