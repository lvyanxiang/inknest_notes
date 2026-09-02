import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/features/library/library_screen.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_conflict_resolution_service.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';
import 'package:inknest_notes/sync/sync_tombstone_restore_service.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';
import 'package:inknest_notes/sync/sync_state.dart';
import 'package:inknest_notes/sync/sync_structural_conflicts.dart';

void main() {
  testWidgets('signed-in startup syncs silently and keeps details in status', (
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
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.text('已上传 2 项本地更改，当前已同步。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('creating a notebook schedules another signed-in sync', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(uploadedOperationCount: 0);

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();
    expect(sync.calls, ['push', 'pull']);

    await tester.tap(find.text('New notebook').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-paged-notebook')));
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull', 'push', 'pull']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('uninitialized cloud library merges without opening a dialog', (
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
        status: IncrementalSyncPullStatus.notInitialized,
      ),
      initialPreview: _firstSignInPreview(
        local: SyncLibraryInventory(),
        cloud: SyncLibraryInventory(notebookIds: const ['cloud-notebook']),
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

    expect(sync.calls, ['push', 'pull', 'inspect', 'restore']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已接收 1 本云端笔记'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('first mixed merge exposes a stored conflict warning silently', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final conflict = _pendingConflict(id: 'first-merge-conflict');
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pullResult: const IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.notInitialized,
      ),
      initialPreview: _firstSignInPreview(
        local: SyncLibraryInventory(notebookIds: const ['shared-notebook']),
        cloud: SyncLibraryInventory(notebookIds: const ['shared-notebook']),
      ),
      firstSignInConflicts: [conflict],
    );

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull', 'inspect', 'merge']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('library-sync-conflicts')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('library-sync-conflicts')));
    await tester.pumpAndSettle();
    expect(find.text(conflict.copyDisplayName), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('structural conflict warning offers local or cloud version', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final conflict = SyncStructuralConflict(
      resourceType: SyncResourceType.page,
      resourceId: 'page-1',
      cloudRevision: 3,
      fields: const ['template', 'rotationQuarterTurns'],
      localMetadata: const {'template': 'grid', 'rotationQuarterTurns': 1},
      baseMetadata: const {'template': 'blank', 'rotationQuarterTurns': 0},
      cloudMetadata: const {'template': 'ruled', 'rotationQuarterTurns': 2},
    );
    final sync = _StartupSyncService(structuralConflicts: [conflict]);

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-conflicts')));
    await tester.pumpAndSettle();
    expect(find.text('页面属性冲突'), findsOneWidget);
    await tester.tap(find.text('页面属性冲突'));
    await tester.pumpAndSettle();
    expect(find.text('使用本机版本'), findsOneWidget);
    expect(find.text('使用云端版本'), findsOneWidget);
    expect(find.textContaining('两个都保留'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shared pull refreshes silently and reports details in status', (
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

    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
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

    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
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

    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
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

    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('library-sync-conflicts')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('library-sync-conflicts')));
    await tester.pumpAndSettle();

    expect(find.text('同步冲突'), findsOneWidget);
    expect(find.text('第 1 页（冲突副本）'), findsOneWidget);
    expect(find.text('1 项待处理；本机与云端版本均已安全保留。'), findsOneWidget);

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

  testWidgets('active Tombstone opens Recently Deleted and can be restored', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final tombstone = CloudSyncTombstone.fromJson({
      'id': 'tombstone-1',
      'resourceType': 'notebook',
      'resourceId': 'notebook-1',
      'baseRevision': 1,
      'resourceRevision': 1,
      'deletedRevision': 2,
      'contentHash': 'a' * 64,
      'content': const {'bookmarkedPageIds': <Object?>[]},
      'deletedByDeviceId': 'device-2',
      'deletedAt': '2026-08-07T00:00:00Z',
      'state': 'active',
      'createdAt': '2026-08-07T00:00:00Z',
    });
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pullResult: IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
        changeCount: 1,
        activeTombstones: [tombstone],
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

    await tester.tap(find.byKey(const ValueKey('library-recently-deleted')));
    await tester.pumpAndSettle();

    expect(find.text('最近删除'), findsOneWidget);
    expect(find.text('已删除的笔记'), findsOneWidget);
    expect(find.textContaining('当前没有永久删除操作'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('restore-tombstone-tombstone-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(sync.restoredTombstoneIds, ['tombstone-1']);
    expect(
      find.byKey(const ValueKey('library-recently-deleted')),
      findsNothing,
    );
    expect(find.textContaining('已删除的笔记已恢复'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('sync status shows progress and then completion', (tester) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final gate = Completer<void>();
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pushGate: gate.future,
    );

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pump();
    await tester.pump();

    final status = find.byKey(const ValueKey('library-sync-status'));
    expect(status, findsOneWidget);
    expect(
      find.descendant(
        of: status,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();

    expect(find.text('同步完成'), findsOneWidget);
    expect(find.text('本地笔记与云端已同步。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('signed-in sync status can start an immediate sync', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(uploadedOperationCount: 0);

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.text('立即同步'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-now-library')));
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull', 'push', 'pull']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('local sync requests are debounced into one cycle', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(uploadedOperationCount: 0);
    final requests = StreamController<void>.broadcast();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          notebookRepository: InMemoryNotebookRepository(),
          authController: controller,
          firstSignInSyncService: sync,
          syncRequests: requests.stream,
          syncDebounceDuration: const Duration(milliseconds: 50),
          foregroundSyncInterval: const Duration(days: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    sync.calls.clear();

    requests.add(null);
    requests.add(null);
    requests.add(null);
    await tester.pump(const Duration(milliseconds: 49));
    expect(sync.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull']);

    await tester.pumpWidget(const SizedBox.shrink());
    await requests.close();
    controller.dispose();
  });

  testWidgets('editor-covered library uploads but defers remote pull', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(uploadedOperationCount: 1);
    final requests = StreamController<void>.broadcast();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: LibraryScreen(
          notebookRepository: InMemoryNotebookRepository(),
          authController: controller,
          firstSignInSyncService: sync,
          syncRequests: requests.stream,
          syncDebounceDuration: const Duration(milliseconds: 1),
          foregroundSyncInterval: const Duration(days: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    sync.calls.clear();

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Editor'))),
      ),
    );
    await tester.pumpAndSettle();
    requests.add(null);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(sync.calls, ['push']);

    await tester.pumpWidget(const SizedBox.shrink());
    await requests.close();
    controller.dispose();
  });

  testWidgets('a sync request received while busy runs a follow-up cycle', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final gate = Completer<void>();
    final sync = _StartupSyncService(
      uploadedOperationCount: 0,
      pushGate: gate.future,
    );
    final requests = StreamController<void>.broadcast();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          notebookRepository: InMemoryNotebookRepository(),
          authController: controller,
          firstSignInSyncService: sync,
          syncRequests: requests.stream,
          syncDebounceDuration: const Duration(milliseconds: 1),
          foregroundSyncInterval: const Duration(days: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(sync.calls, ['push']);

    requests.add(null);
    await tester.pump(const Duration(milliseconds: 1));
    gate.complete();
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'pull', 'push', 'pull']);

    await tester.pumpWidget(const SizedBox.shrink());
    await requests.close();
    controller.dispose();
  });

  testWidgets('foreground resume and interval request synchronization', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(uploadedOperationCount: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          notebookRepository: InMemoryNotebookRepository(),
          authController: controller,
          firstSignInSyncService: sync,
          foregroundSyncInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    sync.calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(sync.calls, ['push', 'pull']);

    sync.calls.clear();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sync.calls, ['push', 'pull']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('failed sync keeps item count and retries from status', (
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
      pushFailuresRemaining: 1,
    );

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.text('同步失败'), findsOneWidget);
    expect(find.textContaining('2 项本地更改仍安全保留'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('retry-library-sync')));
    await tester.pumpAndSettle();

    expect(sync.calls, ['push', 'push', 'pull']);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.text('同步完成'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('delete conflict calmly reports that the edit was preserved', (
    tester,
  ) async {
    final controller = AuthController(
      service: _RestoredAuthService(),
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await controller.initialize();
    final sync = _StartupSyncService(
      uploadedOperationCount: 1,
      preservedDeleteEditCount: 1,
    );

    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
        firstSignInSyncService: sync,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-sync-status')));
    await tester.pumpAndSettle();
    expect(find.text('编辑已保留'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-library-sync')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _StartupSyncService
    implements
        FirstSignInSyncService,
        SyncConflictResolutionService,
        SyncTombstoneRestoreService,
        SyncStructuralConflictResolutionService {
  _StartupSyncService({
    this.uploadedOperationCount = 2,
    this.preservedDeleteEditCount = 0,
    this.pushFailuresRemaining = 0,
    this.pushGate,
    this.initialPreview,
    this.firstSignInConflicts = const [],
    this.structuralConflicts = const [],
    this.pullResult = const IncrementalSyncPullResult(
      status: IncrementalSyncPullStatus.upToDate,
    ),
  });

  final int uploadedOperationCount;
  final int preservedDeleteEditCount;
  int pushFailuresRemaining;
  final Future<void>? pushGate;
  final FirstSignInSyncPreview? initialPreview;
  final List<CloudSyncConflict> firstSignInConflicts;
  List<SyncStructuralConflict> structuralConflicts;
  final IncrementalSyncPullResult pullResult;
  final List<String> calls = [];
  final List<SyncConflictResolution> resolutions = [];
  final List<String> restoredTombstoneIds = [];

  @override
  Future<List<SyncStructuralConflict>> loadStructuralConflicts({
    required String userId,
    required String deviceId,
  }) async => structuralConflicts;

  @override
  Future<SyncStructuralConflictResolutionResult> resolveStructuralConflict({
    required String userId,
    required String deviceId,
    required String conflictId,
    required SyncStructuralConflictResolution resolution,
  }) async {
    structuralConflicts = [
      for (final conflict in structuralConflicts)
        if (conflict.id != conflictId) conflict,
    ];
    return SyncStructuralConflictResolutionResult(
      pendingConflicts: structuralConflicts,
    );
  }

  @override
  Future<SyncTombstoneRestoreResult> restoreTombstone({
    required String userId,
    required String deviceId,
    required String tombstoneId,
  }) async {
    restoredTombstoneIds.add(tombstoneId);
    return const SyncTombstoneRestoreResult(
      pullResult: IncrementalSyncPullResult(
        status: IncrementalSyncPullStatus.applied,
      ),
    );
  }

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
    await pushGate;
    if (structuralConflicts.isNotEmpty) {
      throw IncrementalSyncPushException(
        pendingOperationCount: structuralConflicts.length,
        structuralConflicts: structuralConflicts,
      );
    }
    if (pushFailuresRemaining > 0) {
      pushFailuresRemaining--;
      throw const IncrementalSyncPushException(pendingOperationCount: 2);
    }
    return IncrementalSyncPushResult(
      uploadedOperationCount: uploadedOperationCount,
      preservedConflictCount: preservedDeleteEditCount,
      preservedDeleteEditCount: preservedDeleteEditCount,
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
  Future<FirstSignInSyncPreview> inspect() async {
    calls.add('inspect');
    return initialPreview ?? (throw UnimplementedError());
  }

  @override
  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    calls.add('restore');
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
  }) => throw UnimplementedError();

  @override
  Future<MixedLibraryMergeResult> mergeMixed({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    calls.add('merge');
    return MixedLibraryMergeResult(
      uploadedNotebookCount: 0,
      downloadedNotebookCount: 0,
      transferredAssetCount: 0,
      preservedConflictCount: firstSignInConflicts.length,
      pendingConflicts: firstSignInConflicts,
    );
  }
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
    required String clientInstanceId,
  }) => throw UnimplementedError();

  @override
  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
    required String privacyPolicyVersion,
    required String termsVersion,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<InkNestCloudUser> acceptAgreements({
    required String privacyPolicyVersion,
    required String termsVersion,
  }) => throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountDeletionResult> deleteAccount({required String password}) =>
      throw UnimplementedError();
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
      privacyPolicyVersion: '2026-08-31.1',
      termsVersion: '2026-08-31.1',
      agreementsAcceptedAt: now,
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

FirstSignInSyncPreview _firstSignInPreview({
  required SyncLibraryInventory local,
  required SyncLibraryInventory cloud,
}) {
  final assessment = SyncBootstrapAssessment(local: local, cloud: cloud);
  return FirstSignInSyncPreview(
    bootstrap: CloudSyncBootstrap(
      inventory: cloud,
      baseCursor: 'cursor-bootstrap',
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

CloudSyncConflict _pendingConflict({required String id}) => CloudSyncConflict(
  id: id,
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
