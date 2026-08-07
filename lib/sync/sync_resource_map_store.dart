import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_state.dart';

class SyncResourceMapping {
  const SyncResourceMapping({
    required this.localKey,
    required this.resourceType,
    required this.remoteResourceId,
    required this.revision,
    required this.contentHash,
    this.folderMetadata,
    this.notebookMetadata,
    this.infiniteCanvasMetadata,
  });

  final String localKey;
  final SyncResourceType resourceType;
  final String remoteResourceId;
  final int revision;
  final String contentHash;
  final Map<String, Object?>? folderMetadata;
  final Map<String, Object?>? notebookMetadata;
  final Map<String, Object?>? infiniteCanvasMetadata;

  SyncResourceMapping copyWith({
    int? revision,
    String? contentHash,
    Map<String, Object?>? folderMetadata,
    Map<String, Object?>? notebookMetadata,
    Map<String, Object?>? infiniteCanvasMetadata,
  }) => SyncResourceMapping(
    localKey: localKey,
    resourceType: resourceType,
    remoteResourceId: remoteResourceId,
    revision: revision ?? this.revision,
    contentHash: contentHash ?? this.contentHash,
    folderMetadata: folderMetadata ?? this.folderMetadata,
    notebookMetadata: notebookMetadata ?? this.notebookMetadata,
    infiniteCanvasMetadata:
        infiniteCanvasMetadata ?? this.infiniteCanvasMetadata,
  );

  factory SyncResourceMapping.fromJson(Map<String, Object?> json) {
    final revision = json['revision'];
    final contentHash = json['contentHash'];
    final resourceType = SyncResourceType.fromApiValue(
      json['resourceType']! as String,
    );
    final validHash =
        contentHash is String &&
        (RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash) ||
            (resourceType == SyncResourceType.folder &&
                revision == 0 &&
                contentHash.isEmpty));
    if (revision is! int || revision < 0 || !validHash) {
      throw const FormatException('Invalid synchronization resource mapping.');
    }
    return SyncResourceMapping(
      localKey: json['localKey']! as String,
      resourceType: resourceType,
      remoteResourceId: json['remoteResourceId']! as String,
      revision: revision,
      contentHash: contentHash,
      folderMetadata: json['folderMetadata'] == null
          ? null
          : Map.unmodifiable(
              (json['folderMetadata']! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
            ),
      notebookMetadata: json['notebookMetadata'] == null
          ? null
          : Map.unmodifiable(
              (json['notebookMetadata']! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
            ),
      infiniteCanvasMetadata: json['infiniteCanvasMetadata'] == null
          ? null
          : Map.unmodifiable(
              (json['infiniteCanvasMetadata']! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'localKey': localKey,
    'resourceType': resourceType.apiValue,
    'remoteResourceId': remoteResourceId,
    'revision': revision,
    'contentHash': contentHash,
    if (folderMetadata != null) 'folderMetadata': folderMetadata,
    if (notebookMetadata != null) 'notebookMetadata': notebookMetadata,
    if (infiniteCanvasMetadata != null)
      'infiniteCanvasMetadata': infiniteCanvasMetadata,
  };
}

class FileSyncResourceMapStore {
  FileSyncResourceMapStore({
    required Directory rootDirectory,
    required String userId,
    required String deviceId,
  }) : _file = File(
         '${rootDirectory.path}/sync/$userId/$deviceId/resources.json',
       );

  final File _file;
  Future<void> _writeQueue = Future.value();
  int _temporaryFileCounter = 0;

  Future<List<SyncResourceMapping>> load() async {
    await _writeQueue.catchError((_) {});
    return (await _read()).resources;
  }

  Future<_SyncResourceMapDocument> _read() async {
    if (!await _file.exists()) return const _SyncResourceMapDocument();
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['formatVersion'] != 1) {
      throw const FormatException('Invalid synchronization resource map.');
    }
    final rawResources = decoded['resources'];
    if (rawResources is! List<Object?> ||
        rawResources.any((item) => item is! Map<Object?, Object?>)) {
      throw const FormatException('Invalid synchronization resource map.');
    }
    final resources = rawResources
        .map(
          (item) => SyncResourceMapping.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
    if (resources.map((item) => item.localKey).toSet().length !=
        resources.length) {
      throw const FormatException('Duplicate local synchronization mapping.');
    }
    final rawCloudAssetKeys = decoded['cloudAssetKeys'];
    Set<String> cloudAssetKeys = const {};
    if (rawCloudAssetKeys != null) {
      if (rawCloudAssetKeys is! List<Object?> ||
          rawCloudAssetKeys.any((item) => item is! String)) {
        throw const FormatException('Invalid synchronization asset map.');
      }
      cloudAssetKeys = Set.unmodifiable(rawCloudAssetKeys.cast<String>());
    }
    return _SyncResourceMapDocument(
      resources: resources,
      cloudAssetKeys: cloudAssetKeys,
    );
  }

  Future<SyncResourceMapping?> find(String localKey) async {
    final resources = await load();
    for (final resource in resources) {
      if (resource.localKey == localKey) return resource;
    }
    return null;
  }

  Future<bool> hasCloudAsset(String notebookId, String relativePath) async {
    await _writeQueue.catchError((_) {});
    return (await _read()).cloudAssetKeys.contains(
      cloudAssetSyncKey(notebookId, relativePath),
    );
  }

  Future<void> replaceAll(
    List<SyncResourceMapping> resources, {
    Iterable<String> cloudAssetKeys = const [],
  }) {
    return _enqueueWrite(() async {
      await _write(
        _SyncResourceMapDocument(
          resources: resources,
          cloudAssetKeys: Set.unmodifiable(cloudAssetKeys),
        ),
      );
    });
  }

  Future<void> updateRemote({
    required SyncResourceType resourceType,
    required String remoteResourceId,
    required int revision,
    required String contentHash,
    Map<String, Object?>? notebookMetadata,
    Map<String, Object?>? infiniteCanvasMetadata,
  }) {
    return _enqueueWrite(() async {
      final document = await _read();
      final hasResource = document.resources.any(
        (resource) =>
            resource.resourceType == resourceType &&
            resource.remoteResourceId == remoteResourceId,
      );
      if (!hasResource) {
        throw StateError(
          'The committed resource is missing from the local sync map.',
        );
      }
      final updated = [
        for (final resource in document.resources)
          if (resource.resourceType == resourceType &&
              resource.remoteResourceId == remoteResourceId)
            resource.copyWith(
              revision: revision,
              contentHash: contentHash,
              notebookMetadata: notebookMetadata,
              infiniteCanvasMetadata: infiniteCanvasMetadata,
            )
          else
            resource,
      ];
      await _write(
        _SyncResourceMapDocument(
          resources: updated,
          cloudAssetKeys: document.cloudAssetKeys,
        ),
      );
    });
  }

  Future<void> _enqueueWrite(Future<void> Function() action) {
    final previous = _writeQueue;
    final next = previous.catchError((_) {}).then((_) => action());
    _writeQueue = next;
    return next;
  }

  Future<void> _write(_SyncResourceMapDocument document) async {
    await _file.parent.create(recursive: true);
    final sorted = document.resources.toList()
      ..sort((left, right) => left.localKey.compareTo(right.localKey));
    final sortedAssetKeys = document.cloudAssetKeys.toList()..sort();
    final temporary = File('${_file.path}.tmp-${_temporaryFileCounter++}');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'resources': sorted.map((item) => item.toJson()).toList(),
        'cloudAssetKeys': sortedAssetKeys,
      }),
      flush: true,
    );
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }
}

String notebookSyncLocalKey(String notebookId) => 'notebook:$notebookId';

String folderSyncLocalKey(String folderId) => 'folder:$folderId';

String pageSyncLocalKey(String notebookId, String pageId) =>
    'page:$notebookId:$pageId';

String canvasSyncLocalKey(String notebookId) => 'infinite_canvas:$notebookId';

String cloudAssetSyncKey(String notebookId, String relativePath) =>
    '$notebookId\u0000$relativePath';

Set<String> buildCloudAssetKeys(CloudSyncBootstrap bootstrap) => {
  for (final asset in bootstrap.assets)
    cloudAssetSyncKey(asset.notebookId, asset.relativePath),
};

Future<List<SyncResourceMapping>> buildSyncResourceMappings({
  required NotebookRepository repository,
  required CloudSyncBootstrap bootstrap,
}) async {
  final folders = await repository.listFolders();
  final notebooks = [
    ...await repository.listNotebooks(),
    for (final folder in folders)
      ...await repository.listNotebooks(folderId: folder.id),
    ...await repository.listNotebooks(archived: true),
  ];
  final cloudNotebooks = {
    for (final notebook in bootstrap.notebooks) notebook.id: notebook,
  };
  final mappings = <SyncResourceMapping>[];
  final cloudFolders = {
    for (final folder in bootstrap.folders) folder.id: folder,
  };
  for (final folder in folders) {
    final cloudFolder = cloudFolders[folder.id];
    if (cloudFolder == null) continue;
    mappings.add(
      SyncResourceMapping(
        localKey: folderSyncLocalKey(folder.id),
        resourceType: SyncResourceType.folder,
        remoteResourceId: cloudFolder.id,
        revision: cloudFolder.revision,
        contentHash: cloudFolder.contentHash,
        folderMetadata: {'name': cloudFolder.name},
      ),
    );
  }
  for (final notebook in notebooks) {
    final cloudNotebook = cloudNotebooks[notebook.id];
    if (cloudNotebook == null) continue;
    final cloudPages = notebook.layoutMode.name == 'paged'
        ? (bootstrap.pages
              .where((page) => page.notebookId == notebook.id)
              .toList()
            ..sort((left, right) => left.position.compareTo(right.position)))
        : const <CloudSyncPage>[];
    mappings.add(
      SyncResourceMapping(
        localKey: notebookSyncLocalKey(notebook.id),
        resourceType: SyncResourceType.notebook,
        remoteResourceId: cloudNotebook.id,
        revision: cloudNotebook.revision,
        contentHash: cloudNotebook.contentHash,
        notebookMetadata: notebookSyncMetadata(
          cloudNotebook,
          pageOrder: cloudPages.map((page) => page.id),
        ),
      ),
    );
    if (notebook.layoutMode.name == 'paged') {
      for (final (position, localPageId) in notebook.pageIds.indexed) {
        if (position >= cloudPages.length ||
            cloudPages[position].position != position) {
          continue;
        }
        final cloudPage = cloudPages[position];
        mappings.add(
          SyncResourceMapping(
            localKey: pageSyncLocalKey(notebook.id, localPageId),
            resourceType: SyncResourceType.page,
            remoteResourceId: cloudPage.id,
            revision: cloudPage.revision,
            contentHash: cloudPage.contentHash,
          ),
        );
      }
    } else {
      final cloudCanvases = bootstrap.infiniteCanvases.where(
        (canvas) => canvas.notebookId == notebook.id,
      );
      if (cloudCanvases.length == 1) {
        final cloudCanvas = cloudCanvases.single;
        mappings.add(
          SyncResourceMapping(
            localKey: canvasSyncLocalKey(notebook.id),
            resourceType: SyncResourceType.infiniteCanvas,
            remoteResourceId: cloudCanvas.id,
            revision: cloudCanvas.revision,
            contentHash: cloudCanvas.contentHash,
            infiniteCanvasMetadata: {'background': cloudCanvas.background},
          ),
        );
      }
    }
  }
  return mappings;
}

Map<String, Object?> notebookSyncMetadata(
  CloudSyncNotebook notebook, {
  Iterable<String>? pageOrder,
}) => {
  'title': notebook.title,
  'isArchived': notebook.isArchived,
  'folderId': notebook.folderId,
  if (pageOrder != null) 'pageOrder': pageOrder.toList(),
};

class _SyncResourceMapDocument {
  const _SyncResourceMapDocument({
    this.resources = const [],
    this.cloudAssetKeys = const {},
  });

  final List<SyncResourceMapping> resources;
  final Set<String> cloudAssetKeys;
}
