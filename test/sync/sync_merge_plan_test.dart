import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';

void main() {
  test(
    'plans local upload, cloud download, and shared reconciliation by ID',
    () {
      final assessment = SyncBootstrapAssessment(
        local: SyncLibraryInventory(
          folderIds: ['folder-local', 'folder-shared'],
          notebookIds: ['notebook-local', 'notebook-shared'],
        ),
        cloud: SyncLibraryInventory(
          folderIds: ['folder-cloud', 'folder-shared'],
          notebookIds: ['notebook-cloud', 'notebook-shared'],
        ),
      );

      final plan = SyncMergePlan.fromAssessment(assessment);

      expect(
        plan.actions.map(
          (action) => (action.resourceType, action.kind, action.resourceId),
        ),
        [
          (
            SyncMergeResourceType.folder,
            SyncMergeActionKind.uploadLocal,
            'folder-local',
          ),
          (
            SyncMergeResourceType.folder,
            SyncMergeActionKind.downloadCloud,
            'folder-cloud',
          ),
          (
            SyncMergeResourceType.folder,
            SyncMergeActionKind.reconcileShared,
            'folder-shared',
          ),
          (
            SyncMergeResourceType.notebook,
            SyncMergeActionKind.uploadLocal,
            'notebook-local',
          ),
          (
            SyncMergeResourceType.notebook,
            SyncMergeActionKind.downloadCloud,
            'notebook-cloud',
          ),
          (
            SyncMergeResourceType.notebook,
            SyncMergeActionKind.reconcileShared,
            'notebook-shared',
          ),
        ],
      );
      expect(plan.count(SyncMergeActionKind.uploadLocal), 2);
      expect(plan.count(SyncMergeActionKind.downloadCloud), 2);
      expect(plan.count(SyncMergeActionKind.reconcileShared), 2);
    },
  );

  test('produces a deterministic plan regardless of inventory input order', () {
    SyncMergePlan buildPlan(List<String> localIds, List<String> cloudIds) {
      return SyncMergePlan.fromAssessment(
        SyncBootstrapAssessment(
          local: SyncLibraryInventory(notebookIds: localIds),
          cloud: SyncLibraryInventory(notebookIds: cloudIds),
        ),
      );
    }

    final first = buildPlan(
      ['notebook-z', 'notebook-shared', 'notebook-a'],
      ['notebook-y', 'notebook-shared', 'notebook-b'],
    );
    final retry = buildPlan(
      ['notebook-a', 'notebook-z', 'notebook-shared'],
      ['notebook-shared', 'notebook-b', 'notebook-y'],
    );

    expect(retry.actions.map(_actionKey), first.actions.map(_actionKey));
    expect(first.actions.map(_actionKey), [
      'notebook:uploadLocal:notebook-a',
      'notebook:uploadLocal:notebook-z',
      'notebook:downloadCloud:notebook-b',
      'notebook:downloadCloud:notebook-y',
      'notebook:reconcileShared:notebook-shared',
    ]);
  });

  test('empty libraries produce a no-op plan', () {
    final plan = SyncMergePlan.fromAssessment(
      SyncBootstrapAssessment(
        local: SyncLibraryInventory(),
        cloud: SyncLibraryInventory(),
      ),
    );

    expect(plan.isEmpty, isTrue);
    expect(plan.actions, isEmpty);
  });

  test('rejects corrupt local inventories before planning', () {
    expect(
      () => SyncLibraryInventory(notebookIds: ['duplicate', 'duplicate']),
      throwsFormatException,
    );
    expect(() => SyncLibraryInventory(folderIds: ['']), throwsFormatException);
  });
}

String _actionKey(SyncMergeAction action) {
  return '${action.resourceType.name}:${action.kind.name}:${action.resourceId}';
}
