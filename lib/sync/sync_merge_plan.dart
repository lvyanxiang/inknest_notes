import 'package:inknest_notes/sync/sync_bootstrap.dart';

enum SyncMergeResourceType { folder, notebook }

enum SyncMergeActionKind { uploadLocal, downloadCloud, reconcileShared }

class SyncMergeAction {
  const SyncMergeAction({
    required this.kind,
    required this.resourceType,
    required this.resourceId,
  });

  final SyncMergeActionKind kind;
  final SyncMergeResourceType resourceType;
  final String resourceId;
}

class SyncMergePlan {
  SyncMergePlan._(List<SyncMergeAction> actions)
    : actions = List.unmodifiable(actions);

  factory SyncMergePlan.fromAssessment(SyncBootstrapAssessment assessment) {
    final actions = <SyncMergeAction>[];

    void addActions(
      SyncMergeResourceType resourceType,
      SyncMergeActionKind kind,
      Set<String> resourceIds,
    ) {
      final sortedIds = resourceIds.toList()..sort();
      actions.addAll(
        sortedIds.map(
          (resourceId) => SyncMergeAction(
            kind: kind,
            resourceType: resourceType,
            resourceId: resourceId,
          ),
        ),
      );
    }

    for (final resourceType in SyncMergeResourceType.values) {
      for (final kind in SyncMergeActionKind.values) {
        final resourceIds = switch ((resourceType, kind)) {
          (SyncMergeResourceType.folder, SyncMergeActionKind.uploadLocal) =>
            assessment.localOnlyFolderIds,
          (SyncMergeResourceType.folder, SyncMergeActionKind.downloadCloud) =>
            assessment.cloudOnlyFolderIds,
          (SyncMergeResourceType.folder, SyncMergeActionKind.reconcileShared) =>
            assessment.sharedFolderIds,
          (SyncMergeResourceType.notebook, SyncMergeActionKind.uploadLocal) =>
            assessment.localOnlyNotebookIds,
          (SyncMergeResourceType.notebook, SyncMergeActionKind.downloadCloud) =>
            assessment.cloudOnlyNotebookIds,
          (
            SyncMergeResourceType.notebook,
            SyncMergeActionKind.reconcileShared,
          ) =>
            assessment.sharedNotebookIds,
        };
        addActions(resourceType, kind, resourceIds);
      }
    }

    return SyncMergePlan._(actions);
  }

  final List<SyncMergeAction> actions;

  bool get isEmpty => actions.isEmpty;

  int count(SyncMergeActionKind kind) {
    return actions.where((action) => action.kind == kind).length;
  }
}
