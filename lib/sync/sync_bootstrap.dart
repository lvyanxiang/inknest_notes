import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

enum SyncLibraryPresence { empty, localOnly, cloudOnly, localAndCloud }

enum SyncBootstrapRecommendation { nothingToDo, merge }

class SyncLibraryInventory {
  factory SyncLibraryInventory({
    Iterable<String> folderIds = const [],
    Iterable<String> notebookIds = const [],
  }) {
    final folders = folderIds.toList();
    final notebooks = notebookIds.toList();
    _validateStableIds(folders, field: 'folderIds');
    _validateStableIds(notebooks, field: 'notebookIds');
    return SyncLibraryInventory._(
      folderIds: Set.unmodifiable(folders),
      notebookIds: Set.unmodifiable(notebooks),
    );
  }

  const SyncLibraryInventory._({
    required this.folderIds,
    required this.notebookIds,
  });

  final Set<String> folderIds;
  final Set<String> notebookIds;

  bool get hasLibrary => folderIds.isNotEmpty || notebookIds.isNotEmpty;
}

class CloudSyncBootstrap {
  CloudSyncBootstrap({
    required this.inventory,
    required this.baseCursor,
    required List<CloudSyncFolder> folders,
    required List<CloudSyncNotebook> notebooks,
    required List<CloudSyncPage> pages,
    required List<CloudSyncInfiniteCanvas> infiniteCanvases,
    required List<CloudSyncAsset> assets,
  }) : folders = List.unmodifiable(folders),
       notebooks = List.unmodifiable(notebooks),
       pages = List.unmodifiable(pages),
       infiniteCanvases = List.unmodifiable(infiniteCanvases),
       assets = List.unmodifiable(assets);

  final SyncLibraryInventory inventory;
  final String baseCursor;
  final List<CloudSyncFolder> folders;
  final List<CloudSyncNotebook> notebooks;
  final List<CloudSyncPage> pages;
  final List<CloudSyncInfiniteCanvas> infiniteCanvases;
  final List<CloudSyncAsset> assets;

  factory CloudSyncBootstrap.fromJson(Map<String, Object?> json) {
    final folderIds = requiredUniqueStringList(json, 'folderIds');
    final notebookIds = requiredUniqueStringList(json, 'notebookIds');
    final folders = requiredObjectList(
      json,
      'folders',
    ).map(CloudSyncFolder.fromJson).toList();
    final notebooks = requiredObjectList(
      json,
      'notebooks',
    ).map(CloudSyncNotebook.fromJson).toList();
    final pages = requiredObjectList(
      json,
      'pages',
    ).map(CloudSyncPage.fromJson).toList();
    final infiniteCanvases = requiredObjectList(
      json,
      'infiniteCanvases',
    ).map(CloudSyncInfiniteCanvas.fromJson).toList();
    final assets = requiredObjectList(
      json,
      'assets',
    ).map(CloudSyncAsset.fromJson).toList();
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
        counts['folders'] != folders.length ||
        counts['notebooks'] != notebooks.length ||
        counts['pages'] != pages.length ||
        counts['infiniteCanvases'] != infiniteCanvases.length ||
        counts['assets'] != assets.length) {
      throw const FormatException('Bootstrap resource counts do not match.');
    }
    validateUniqueResourceIds(folders.map((item) => item.id), 'folders');
    validateUniqueResourceIds(notebooks.map((item) => item.id), 'notebooks');
    validateUniqueResourceIds(pages.map((item) => item.id), 'pages');
    validateUniqueResourceIds(
      infiniteCanvases.map((item) => item.id),
      'infiniteCanvases',
    );
    validateUniqueResourceIds(assets.map((item) => item.id), 'assets');
    _validateStableIds(pages.map((item) => item.id).toList(), field: 'pages');
    _validateStableIds(
      infiniteCanvases.map((item) => item.id).toList(),
      field: 'infiniteCanvases',
    );
    _validateStableIds(assets.map((item) => item.id).toList(), field: 'assets');
    validateUniqueResourceIds(
      assets.map((item) => '${item.notebookId}:${item.relativePath}'),
      'asset relative paths',
    );
    if (!sameStringSet(folderIds, folders.map((item) => item.id)) ||
        !sameStringSet(notebookIds, notebooks.map((item) => item.id))) {
      throw const FormatException(
        'Bootstrap stable-ID inventory does not match its snapshots.',
      );
    }
    final folderIdSet = folderIds.toSet();
    if (notebooks.any(
      (item) => item.folderId != null && !folderIdSet.contains(item.folderId),
    )) {
      throw const FormatException(
        'Bootstrap notebook references an unknown folder.',
      );
    }
    final notebookIdSet = notebookIds.toSet();
    if (pages.any((item) => !notebookIdSet.contains(item.notebookId)) ||
        infiniteCanvases.any(
          (item) => !notebookIdSet.contains(item.notebookId),
        ) ||
        assets.any((item) => !notebookIdSet.contains(item.notebookId))) {
      throw const FormatException(
        'Bootstrap child resource references an unknown notebook.',
      );
    }
    final notebookLayouts = {
      for (final notebook in notebooks) notebook.id: notebook.layoutMode,
    };
    if (pages.any((item) => notebookLayouts[item.notebookId] != 'paged') ||
        infiniteCanvases.any(
          (item) => notebookLayouts[item.notebookId] != 'infiniteCanvas',
        )) {
      throw const FormatException(
        'Bootstrap content does not match its notebook layout.',
      );
    }
    final inventory = SyncLibraryInventory(
      folderIds: folderIds,
      notebookIds: notebookIds,
    );
    if (hasCloudLibrary != inventory.hasLibrary) {
      throw const FormatException('Bootstrap library presence does not match.');
    }
    return CloudSyncBootstrap(
      inventory: inventory,
      baseCursor: baseCursor,
      folders: folders,
      notebooks: notebooks,
      pages: pages,
      infiniteCanvases: infiniteCanvases,
      assets: assets,
    );
  }
}

class CloudSyncFolder {
  const CloudSyncFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CloudSyncFolder.fromJson(Map<String, Object?> json) {
    return CloudSyncFolder(
      id: requiredString(json, 'id'),
      name: requiredString(json, 'name'),
      createdAt: requiredDateTime(json, 'createdAt'),
      updatedAt: requiredDateTime(json, 'updatedAt'),
    );
  }
}

class CloudSyncNotebook {
  CloudSyncNotebook({
    required this.id,
    required this.folderId,
    required this.title,
    required this.layoutMode,
    required this.isArchived,
    required this.revision,
    required this.contentHash,
    required Map<String, Object?> content,
    required this.conflictOf,
    required this.createdAt,
    required this.updatedAt,
  }) : content = Map.unmodifiable(content);

  final String id;
  final String? folderId;
  final String title;
  final String layoutMode;
  final bool isArchived;
  final int revision;
  final String contentHash;
  final Map<String, Object?> content;
  final String? conflictOf;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CloudSyncNotebook.fromJson(Map<String, Object?> json) {
    final layoutMode = requiredString(json, 'layoutMode');
    final archived = json['isArchived'];
    if (!const {'paged', 'infiniteCanvas'}.contains(layoutMode) ||
        archived is! bool) {
      throw const FormatException('Invalid notebook snapshot metadata.');
    }
    final revision = requiredNonNegativeInt(json, 'revision');
    return CloudSyncNotebook(
      id: requiredString(json, 'id'),
      folderId: _optionalStableId(json, 'folderId'),
      title: requiredString(json, 'title'),
      layoutMode: layoutMode,
      isArchived: archived,
      revision: revision,
      contentHash: _revisionHash(json, revision),
      content: copyJsonObject(json['content'], 'notebook.content'),
      conflictOf: _optionalStableId(json, 'conflictOf'),
      createdAt: requiredDateTime(json, 'createdAt'),
      updatedAt: requiredDateTime(json, 'updatedAt'),
    );
  }
}

class CloudSyncPage {
  CloudSyncPage({
    required this.id,
    required this.notebookId,
    required this.position,
    required this.width,
    required this.height,
    required this.coordinateSpaceVersion,
    required this.rotationQuarterTurns,
    required this.template,
    required this.revision,
    required this.contentHash,
    required Map<String, Object?> content,
    required this.conflictOf,
    required this.createdAt,
    required this.updatedAt,
  }) : content = Map.unmodifiable(content);

  final String id;
  final String notebookId;
  final int position;
  final double width;
  final double height;
  final Object? coordinateSpaceVersion;
  final int rotationQuarterTurns;
  final String template;
  final int revision;
  final String contentHash;
  final Map<String, Object?> content;
  final String? conflictOf;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CloudSyncPage.fromJson(Map<String, Object?> json) {
    final rotation = requiredNonNegativeInt(json, 'rotationQuarterTurns');
    if (rotation > 3) {
      throw const FormatException(
        'rotationQuarterTurns must be between 0 and 3.',
      );
    }
    final revision = requiredNonNegativeInt(json, 'revision');
    return CloudSyncPage(
      id: requiredString(json, 'id'),
      notebookId: requiredString(json, 'notebookId'),
      position: requiredNonNegativeInt(json, 'position'),
      width: requiredPositiveDouble(json, 'width'),
      height: requiredPositiveDouble(json, 'height'),
      coordinateSpaceVersion: _copyJsonValue(json['coordinateSpaceVersion']),
      rotationQuarterTurns: rotation,
      template: requiredString(json, 'template'),
      revision: revision,
      contentHash: _revisionHash(json, revision),
      content: copyJsonObject(json['content'], 'page.content'),
      conflictOf: _optionalStableId(json, 'conflictOf'),
      createdAt: requiredDateTime(json, 'createdAt'),
      updatedAt: requiredDateTime(json, 'updatedAt'),
    );
  }
}

class CloudSyncInfiniteCanvas {
  CloudSyncInfiniteCanvas({
    required this.id,
    required this.notebookId,
    required this.background,
    required this.revision,
    required this.contentHash,
    required Map<String, Object?> content,
    required this.createdAt,
    required this.updatedAt,
  }) : content = Map.unmodifiable(content);

  final String id;
  final String notebookId;
  final String background;
  final int revision;
  final String contentHash;
  final Map<String, Object?> content;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CloudSyncInfiniteCanvas.fromJson(Map<String, Object?> json) {
    final revision = requiredNonNegativeInt(json, 'revision');
    return CloudSyncInfiniteCanvas(
      id: requiredString(json, 'id'),
      notebookId: requiredString(json, 'notebookId'),
      background: requiredString(json, 'background'),
      revision: revision,
      contentHash: _revisionHash(json, revision),
      content: copyJsonObject(json['content'], 'infiniteCanvas.content'),
      createdAt: requiredDateTime(json, 'createdAt'),
      updatedAt: requiredDateTime(json, 'updatedAt'),
    );
  }
}

class CloudSyncAsset {
  const CloudSyncAsset({
    required this.id,
    required this.notebookId,
    required this.kind,
    required this.originalFilename,
    required this.relativePath,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String notebookId;
  final String kind;
  final String originalFilename;
  final String relativePath;
  final String contentType;
  final int byteSize;
  final String sha256;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CloudSyncAsset.fromJson(Map<String, Object?> json) {
    final kind = requiredString(json, 'kind');
    final relativePath = requiredString(json, 'relativePath');
    final byteSize = json['byteSize'];
    if (!const {'pdf', 'image', 'audio'}.contains(kind) ||
        byteSize is! int ||
        byteSize <= 0) {
      throw const FormatException('Invalid asset snapshot metadata.');
    }
    validateNotebookAssetPath(relativePath, kind: kind);
    return CloudSyncAsset(
      id: requiredString(json, 'id'),
      notebookId: requiredString(json, 'notebookId'),
      kind: kind,
      originalFilename: requiredString(json, 'originalFilename'),
      relativePath: relativePath,
      contentType: requiredString(json, 'contentType'),
      byteSize: byteSize,
      sha256: requiredSha256(json, 'sha256'),
      createdAt: requiredDateTime(json, 'createdAt'),
      updatedAt: requiredDateTime(json, 'updatedAt'),
    );
  }
}

class CloudAssetDownload {
  const CloudAssetDownload({
    required this.assetId,
    required this.filename,
    required this.relativePath,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.downloadUrl,
    required this.expiresAt,
  });

  final String assetId;
  final String filename;
  final String relativePath;
  final String contentType;
  final int byteSize;
  final String sha256;
  final Uri downloadUrl;
  final DateTime expiresAt;

  factory CloudAssetDownload.fromJson(Map<String, Object?> json) {
    final byteSize = json['byteSize'];
    final method = json['method'];
    final rawUrl = requiredString(json, 'downloadUrl');
    final downloadUrl = Uri.tryParse(rawUrl);
    final relativePath = requiredString(json, 'relativePath');
    if (byteSize is! int ||
        byteSize <= 0 ||
        method != 'GET' ||
        downloadUrl == null ||
        !downloadUrl.hasAuthority ||
        !const {'http', 'https'}.contains(downloadUrl.scheme)) {
      throw const FormatException('Invalid asset download response.');
    }
    return CloudAssetDownload(
      assetId: requiredString(json, 'assetId'),
      filename: requiredString(json, 'filename'),
      relativePath: relativePath,
      contentType: requiredString(json, 'contentType'),
      byteSize: byteSize,
      sha256: requiredSha256(json, 'sha256'),
      downloadUrl: downloadUrl,
      expiresAt: requiredDateTime(json, 'expiresAt'),
    );
  }

  void verifyMatches(CloudSyncAsset asset) {
    validateNotebookAssetPath(relativePath, kind: asset.kind);
    if (assetId != asset.id ||
        filename != asset.originalFilename ||
        relativePath != asset.relativePath ||
        contentType != asset.contentType ||
        byteSize != asset.byteSize ||
        sha256 != asset.sha256) {
      throw const FormatException(
        'Asset download metadata does not match the bootstrap snapshot.',
      );
    }
  }
}

void validateNotebookAssetPath(String value, {required String kind}) {
  if (value.isEmpty ||
      value.length > 1024 ||
      value.trim() != value ||
      value.contains('\\') ||
      value.startsWith('/') ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..') ||
      !value.startsWith('assets/')) {
    throw const FormatException('Invalid notebook-relative asset path.');
  }
  final segments = value.split('/');
  final requiredDirectory = switch (kind) {
    'image' => 'images',
    'audio' => 'audio',
    _ => null,
  };
  if (requiredDirectory != null &&
      (segments.length < 3 || segments[1] != requiredDirectory)) {
    throw const FormatException('Asset path does not match its kind.');
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

String? _optionalStableId(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw FormatException('$field must be a non-empty string or null.');
  }
  return value;
}

String _revisionHash(Map<String, Object?> json, int revision) {
  final value = json['contentHash'];
  if (revision == 0 && value == '') {
    return '';
  }
  return requiredSha256(json, 'contentHash');
}

Object? _copyJsonValue(Object? value) {
  return switch (value) {
    null || bool() || String() || num() => value,
    List<Object?>() => value.map(_copyJsonValue).toList(growable: false),
    Map<Object?, Object?>() when value.keys.every((key) => key is String) => {
      for (final entry in value.entries)
        entry.key as String: _copyJsonValue(entry.value),
    },
    _ => throw const FormatException(
      'coordinateSpaceVersion must contain only JSON values.',
    ),
  };
}

void _validateStableIds(List<String> items, {required String field}) {
  final safeId = RegExp(r'^[A-Za-z0-9._-]+$');
  if (items.any(
        (item) =>
            item.isEmpty ||
            item.length > 128 ||
            item.trim() != item ||
            !safeId.hasMatch(item),
      ) ||
      items.toSet().length != items.length) {
    throw FormatException('$field must contain unique, path-safe stable IDs.');
  }
}
