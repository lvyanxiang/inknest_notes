import 'package:inknest_notes/storage/notebook_repository.dart';

enum SyncLibraryPresence { empty, localOnly, cloudOnly, localAndCloud }

enum SyncBootstrapRecommendation { nothingToDo, merge }

class SyncLibraryInventory {
  SyncLibraryInventory({
    Iterable<String> folderIds = const [],
    Iterable<String> notebookIds = const [],
  }) : folderIds = Set.unmodifiable(folderIds),
       notebookIds = Set.unmodifiable(notebookIds);

  final Set<String> folderIds;
  final Set<String> notebookIds;

  bool get hasLibrary => folderIds.isNotEmpty || notebookIds.isNotEmpty;
}

class CloudSyncBootstrap {
  CloudSyncBootstrap({required this.inventory, required this.baseCursor});

  final SyncLibraryInventory inventory;
  final String baseCursor;

  factory CloudSyncBootstrap.fromJson(Map<String, Object?> json) {
    final folderIds = _stringList(json['folderIds'], field: 'folderIds');
    final notebookIds = _stringList(json['notebookIds'], field: 'notebookIds');
    final hasCloudLibrary = json['hasCloudLibrary'];
    final baseCursor = json['baseCursor'];
    final counts = json['counts'];
    if (hasCloudLibrary is! bool ||
        baseCursor is! String ||
        baseCursor.isEmpty) {
      throw const FormatException(
        'Invalid synchronization bootstrap response.',
      );
    }
    if (counts is! Map<Object?, Object?> ||
        counts['folders'] != folderIds.length ||
        counts['notebooks'] != notebookIds.length) {
      throw const FormatException('Bootstrap resource counts do not match.');
    }
    final inventory = SyncLibraryInventory(
      folderIds: folderIds,
      notebookIds: notebookIds,
    );
    if (hasCloudLibrary != inventory.hasLibrary) {
      throw const FormatException('Bootstrap library presence does not match.');
    }
    return CloudSyncBootstrap(inventory: inventory, baseCursor: baseCursor);
  }
}

class SyncBootstrapAssessment {
  SyncBootstrapAssessment({
    required SyncLibraryInventory local,
    required SyncLibraryInventory cloud,
  }) : presence = switch ((local.hasLibrary, cloud.hasLibrary)) {
         (false, false) => SyncLibraryPresence.empty,
         (true, false) => SyncLibraryPresence.localOnly,
         (false, true) => SyncLibraryPresence.cloudOnly,
         (true, true) => SyncLibraryPresence.localAndCloud,
       },
       localOnlyFolderIds = Set.unmodifiable(
         local.folderIds.difference(cloud.folderIds),
       ),
       cloudOnlyFolderIds = Set.unmodifiable(
         cloud.folderIds.difference(local.folderIds),
       ),
       sharedFolderIds = Set.unmodifiable(
         local.folderIds.intersection(cloud.folderIds),
       ),
       localOnlyNotebookIds = Set.unmodifiable(
         local.notebookIds.difference(cloud.notebookIds),
       ),
       cloudOnlyNotebookIds = Set.unmodifiable(
         cloud.notebookIds.difference(local.notebookIds),
       ),
       sharedNotebookIds = Set.unmodifiable(
         local.notebookIds.intersection(cloud.notebookIds),
       );

  final SyncLibraryPresence presence;
  final Set<String> localOnlyFolderIds;
  final Set<String> cloudOnlyFolderIds;
  final Set<String> sharedFolderIds;
  final Set<String> localOnlyNotebookIds;
  final Set<String> cloudOnlyNotebookIds;
  final Set<String> sharedNotebookIds;

  SyncBootstrapRecommendation get recommendation =>
      presence == SyncLibraryPresence.empty
      ? SyncBootstrapRecommendation.nothingToDo
      : SyncBootstrapRecommendation.merge;
}

Future<SyncLibraryInventory> readLocalSyncLibraryInventory(
  NotebookRepository repository,
) async {
  final folders = await repository.listFolders();
  final notebooks = [
    ...await repository.listNotebooks(),
    for (final folder in folders)
      ...await repository.listNotebooks(folderId: folder.id),
    ...await repository.listNotebooks(archived: true),
  ];
  return SyncLibraryInventory(
    folderIds: folders.map((folder) => folder.id),
    notebookIds: notebooks.map((notebook) => notebook.id),
  );
}

List<String> _stringList(Object? value, {required String field}) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$field must be a list of strings.');
  }
  final items = value.cast<String>();
  if (items.any((item) => item.isEmpty) ||
      items.toSet().length != items.length) {
    throw FormatException('$field must contain unique, non-empty IDs.');
  }
  return items;
}
