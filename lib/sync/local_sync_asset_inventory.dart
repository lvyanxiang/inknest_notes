import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_resource_map_store.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

Future<List<LocalSyncAsset>> collectLocalSyncAssets(
  NotebookRepository repository, {
  required Set<String> notebookIds,
  Set<String> knownCloudAssetKeys = const {},
}) async {
  final folders = await repository.listFolders();
  final notebooksById = <String, Notebook>{
    for (final notebook in await repository.listNotebooks())
      notebook.id: notebook,
    for (final folder in folders)
      for (final notebook in await repository.listNotebooks(
        folderId: folder.id,
      ))
        notebook.id: notebook,
    for (final notebook in await repository.listNotebooks(archived: true))
      notebook.id: notebook,
  };
  final assets = <String, LocalSyncAsset>{};
  final notebooks =
      notebooksById.values
          .where((notebook) => notebookIds.contains(notebook.id))
          .toList()
        ..sort((left, right) => left.id.compareTo(right.id));

  for (final notebook in notebooks) {
    if (notebook.layoutMode == NotebookLayoutMode.paged) {
      for (final pageId in notebook.pageIds) {
        final page = await repository.loadPage(notebook, pageId);
        final background = page.pdfBackground;
        if (background != null) {
          await _addAsset(
            assets,
            notebook,
            background.assetPath,
            File(background.filePath),
            'pdf',
            knownCloudAssetKeys,
          );
        }
        for (final image in page.images) {
          await _addAsset(
            assets,
            notebook,
            image.assetPath,
            File(image.filePath),
            'image',
            knownCloudAssetKeys,
          );
        }
      }
    } else {
      final canvas = await repository.loadInfiniteCanvas(notebook);
      for (final image in canvas.images) {
        await _addAsset(
          assets,
          notebook,
          image.assetPath,
          File(image.filePath),
          'image',
          knownCloudAssetKeys,
        );
      }
    }
    for (final recording in notebook.audioRecordings) {
      await _addAsset(
        assets,
        notebook,
        recording.assetPath,
        File(recording.filePath),
        'audio',
        knownCloudAssetKeys,
      );
    }
  }

  return assets.values.toList()
    ..sort((left, right) => left.id.compareTo(right.id));
}

Future<LocalSyncAsset> createLocalSyncAsset({
  required Notebook notebook,
  required String relativePath,
  required File file,
  required String kind,
}) async {
  validateNotebookAssetPath(relativePath, kind: kind);
  if (!await file.exists()) {
    throw StateError('A referenced local attachment is missing.');
  }
  final byteSize = await file.length();
  if (byteSize <= 0) {
    throw StateError('A referenced local attachment is empty.');
  }
  final digest = await sha256.bind(file.openRead()).first;
  final filename = relativePath.split('/').last;
  return LocalSyncAsset(
    id: syncAssetId(notebook.id, relativePath),
    notebookId: notebook.id,
    kind: kind,
    filename: filename,
    relativePath: relativePath,
    contentType: syncAssetContentType(filename, kind),
    byteSize: byteSize,
    sha256: digest.toString(),
    file: file,
  );
}

String syncAssetId(String notebookId, String path) =>
    'asset-${sha256.convert(utf8.encode('$notebookId\u0000$path')).toString().substring(0, 40)}';

String syncAssetContentType(String filename, String kind) {
  final extension = filename.toLowerCase().split('.').last;
  return switch ((kind, extension)) {
    ('pdf', _) => 'application/pdf',
    ('image', 'png') => 'image/png',
    ('image', 'jpg') || ('image', 'jpeg') => 'image/jpeg',
    ('image', 'webp') => 'image/webp',
    ('image', 'heic') => 'image/heic',
    ('image', 'heif') => 'image/heif',
    ('audio', 'm4a') || ('audio', 'mp4') => 'audio/mp4',
    ('audio', 'mp3') => 'audio/mpeg',
    ('audio', 'aac') => 'audio/aac',
    ('audio', 'ogg') => 'audio/ogg',
    ('audio', 'webm') => 'audio/webm',
    ('audio', 'wav') => 'audio/wav',
    _ => throw StateError('Unsupported local attachment type.'),
  };
}

Future<void> _addAsset(
  Map<String, LocalSyncAsset> assets,
  Notebook notebook,
  String relativePath,
  File file,
  String kind,
  Set<String> knownCloudAssetKeys,
) async {
  final key = '${notebook.id}:$relativePath';
  if (assets.containsKey(key) ||
      knownCloudAssetKeys.contains(
        cloudAssetSyncKey(notebook.id, relativePath),
      )) {
    return;
  }
  assets[key] = await createLocalSyncAsset(
    notebook: notebook,
    relativePath: relativePath,
    file: file,
    kind: kind,
  );
}
