import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/sync/first_sign_in_sync_dialog.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';

void main() {
  testWidgets('cloud-only preview confirms a real restore', (tester) async {
    final service = _FakeFirstSignInSyncService(
      preview: _preview(
        local: SyncLibraryInventory(),
        cloud: SyncLibraryInventory(notebookIds: const ['cloud-notebook']),
      ),
    );
    FirstSignInSyncDialogResult? result;
    await tester.pumpWidget(
      _TestHost(
        onOpen: (context) async {
          result = await showFirstSignInSyncDialog(
            context: context,
            service: service,
            session: _session(),
          );
          return result;
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('正在检查此设备和云端笔记…'), findsOneWidget);
    await tester.pump();

    expect(find.text('安全合并笔记'), findsOneWidget);
    expect(find.text('云端待下载'), findsOneWidget);
    expect(find.text('1 项'), findsOneWidget);
    await tester.tap(find.text('合并（推荐）'));
    await tester.pump();

    expect(service.restoreCalls, 1);
    expect(result?.restoreResult?.downloadedNotebookCount, 1);
    expect(
      find.byKey(const ValueKey('first-sign-in-sync-dialog')),
      findsNothing,
    );
  });

  testWidgets('mixed library preview confirms coordinated Merge', (
    tester,
  ) async {
    final service = _FakeFirstSignInSyncService(
      preview: _preview(
        local: SyncLibraryInventory(notebookIds: const ['local-notebook']),
        cloud: SyncLibraryInventory(notebookIds: const ['cloud-notebook']),
      ),
    );
    await tester.pumpWidget(
      _TestHost(
        onOpen: (context) => showFirstSignInSyncDialog(
          context: context,
          service: service,
          session: _session(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('不会按同名笔记覆盖'), findsOneWidget);
    expect(find.text('合并（推荐）'), findsOneWidget);
    await tester.tap(find.text('合并（推荐）'));
    await tester.pump();
    expect(service.restoreCalls, 1);
  });

  testWidgets('local-only preview uploads after confirmation', (tester) async {
    final service = _FakeFirstSignInSyncService(
      preview: _preview(
        local: SyncLibraryInventory(notebookIds: const ['local-notebook']),
        cloud: SyncLibraryInventory(),
      ),
    );
    await tester.pumpWidget(
      _TestHost(
        onOpen: (context) => showFirstSignInSyncDialog(
          context: context,
          service: service,
          session: _session(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    expect(find.text('合并（推荐）'), findsOneWidget);
    await tester.tap(find.text('合并（推荐）'));
    await tester.pump();

    expect(service.restoreCalls, 1);
    expect(
      find.byKey(const ValueKey('first-sign-in-sync-dialog')),
      findsNothing,
    );
  });

  testWidgets('inspection failure keeps an offline exit and retry', (
    tester,
  ) async {
    final service = _FakeFirstSignInSyncService(
      preview: _preview(
        local: SyncLibraryInventory(),
        cloud: SyncLibraryInventory(),
      ),
      inspectionError: StateError('offline'),
    );
    await tester.pumpWidget(
      _TestHost(
        onOpen: (context) => showFirstSignInSyncDialog(
          context: context,
          service: service,
          session: _session(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('检查未完成'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('离线继续'), findsOneWidget);
  });
}

class _TestHost extends StatelessWidget {
  const _TestHost({required this.onOpen});

  final Future<Object?> Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => onOpen(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }
}

class _FakeFirstSignInSyncService implements FirstSignInSyncService {
  _FakeFirstSignInSyncService({required this.preview, this.inspectionError});

  final FirstSignInSyncPreview preview;
  final Object? inspectionError;
  int restoreCalls = 0;

  @override
  Future<FirstSignInSyncPreview> inspect() async {
    if (inspectionError case final error?) throw error;
    return preview;
  }

  @override
  Future<BootstrapRestoreResult> restoreCloudOnly({
    required FirstSignInSyncPreview preview,
    required String userId,
    required String deviceId,
  }) async {
    restoreCalls++;
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
    restoreCalls++;
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
    restoreCalls++;
    return const MixedLibraryMergeResult(
      uploadedNotebookCount: 1,
      downloadedNotebookCount: 1,
      transferredAssetCount: 2,
      preservedConflictCount: 0,
    );
  }
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

InkNestAuthSession _session() {
  final now = DateTime.utc(2026, 8, 6);
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
