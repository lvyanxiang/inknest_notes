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
import 'package:inknest_notes/sync/sync_conflict_resolution_service.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';

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

  testWidgets('remote notebook deletion reports preserved recovery copy', (
    tester,
  ) async {
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
        changeCount: 2,
        deletedNotebookCount: 1,
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

    expect(find.textContaining('本地恢复副本已保留'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('remote page deletion reports preserved recovery copy', (
    tester,
  ) async {
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
        changeCount: 2,
        deletedPageCount: 1,
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

    expect(find.textContaining('可恢复的本地页面副本已保留'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('pending conflict survives sync and opens from the library', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final conflict = CloudSyncConflict(
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
      createdAt: DateTime.utc(2026, 8, 7),
    );
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pullResult: IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: 1,
        receivedConflictCount: 1,
        pendingConflicts: [conflict],
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

    expect(find.textContaining('1 个同步冲突待处理'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-sync-conflicts')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('library-sync-conflicts')));
    await tester.pumpAndSettle();

    expect(find.text('同步冲突'), findsOneWidget);
    expect(find.text('第 1 页（冲突副本）'), findsOneWidget);
    expect(find.text('1 项待处理；两个版本都已安全保留。'), findsOneWidget);

    await tester.tap(find.text('第 1 页（冲突副本）'));
    await tester.pumpAndSettle();

    expect(find.text('处理同步冲突'), findsOneWidget);
    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.byKey(const ValueKey('conflict-keep-both')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conflict-keep-original')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('conflict-use-conflict')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conflict-keep-original')));
    await tester.pumpAndSettle();
    expect(find.text('确认保留原版本？'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conflict-use-conflict')));
    await tester.pumpAndSettle();
    expect(find.text('确认使用冲突版本？'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conflict-keep-both')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(sync.resolutions, [SyncConflictResolution.keepBoth]);
    expect(find.byKey(const ValueKey('library-sync-conflicts')), findsNothing);
    expect(find.text('处理同步冲突'), findsNothing);
    expect(find.textContaining('两个都保留完成'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _StartupSyncService
    implements FirstSignInSyncService, SyncConflictResolutionService {
  _StartupSyncService({
    this.uploadedOperationCount = 2,
    this.pullResult = const IncrementalSyncPullResult(
      status: IncrementalSyncPullStatus.upToDate,
    ),
  });

  final int uploadedOperationCount;
  final IncrementalSyncPullResult pullResult;
  final List<String> calls = [];
  final List<SyncConflictResolution> resolutions = [];

  @override
  Future<SyncConflictResolutionResult> resolveConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncConflictResolution resolution,
  }) async {
    resolutions.add(resolution);
    return const SyncConflictResolutionResult(
      pullResult: IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
      ),
    );
  }

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
