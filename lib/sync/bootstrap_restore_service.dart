import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/sync/file_sync_state_store.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';

typedef BootstrapApplyCheckpoint = Future<void> Function(String checkpoint);

class BootstrapAssetVerificationException extends StateError {
  BootstrapAssetVerificationException(this.assetId, super.message);

  final String assetId;
}

class BootstrapAtomicApplyException extends StateError {
  BootstrapAtomicApplyException(super.message);
}

class BootstrapRestoreResult {
  const BootstrapRestoreResult({
    required this.downloadedNotebookCount,
    required this.downloadedAssetCount,
    required this.cursorPersisted,
  });

  final int downloadedNotebookCount;
  final int downloadedAssetCount;
  final bool cursorPersisted;
}

/// Downloads a bootstrap snapshot into disposable storage and applies only
/// cloud-only roots to the file-backed library.
///
/// Existing stable IDs are never replaced. Callers may defer bootstrap Cursor
/// persistence until resource mappings and other handoff metadata are durable;
/// mixed-library merges still need upload/shared-revision reconciliation first.
class BootstrapRestoreService {
  BootstrapRestoreService({
    required this.rootDirectory,
    required this.assetClient,
    required this.syncStateStore,
    DateTime Function()? clock,
    Random? random,
    this.checkpoint,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       assert(rootDirectory.path != '');

  final Directory rootDirectory;
  final CloudAssetTransferClient assetClient;
  final FileSyncStateStore syncStateStore;
  final BootstrapApplyCheckpoint? checkpoint;
  final DateTime Function() _clock;
  final Random _random;

  Directory get _notebooksDirectory =>
      Directory('${rootDirectory.path}/notebooks');

  Future<BootstrapRestoreResult> downloadAndApplyCloudOnly({
    required CloudSyncBootstrap bootstrap,
    required SyncBootstrapAssessment assessment,
    required bool persistCursor,
  }) async {
    final cloudNotebookIds = assessment.cloudOnlyNotebookIds;
    final cloudFolderIds = assessment.cloudOnlyFolderIds;
    final stagingDirectory = Directory(
      '${rootDirectory.path}/sync/bootstrap-staging/${_stagingId()}',
    );

    try {
      final staged = await _stage(
        bootstrap: bootstrap,
        cloudNotebookIds: cloudNotebookIds,
        cloudFolderIds: cloudFolderIds,
        stagingDirectory: stagingDirectory,
      );
      await _apply(staged);

      final cursorCanAdvance =
          assessment.localOnlyFolderIds.isEmpty &&
          assessment.localOnlyNotebookIds.isEmpty &&
          assessment.sharedFolderIds.isEmpty &&
          assessment.sharedNotebookIds.isEmpty;
      if (cursorCanAdvance && persistCursor) {
        await syncStateStore.markChangesPageApplied(bootstrap.baseCursor);
      }
      return BootstrapRestoreResult(
        downloadedNotebookCount: staged.notebooks.length,
        downloadedAssetCount: staged.assetCount,
        cursorPersisted: cursorCanAdvance && persistCursor,
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }

  Future<_StagedBootstrap> _stage({
    required CloudSyncBootstrap bootstrap,
    required Set<String> cloudNotebookIds,
    required Set<String> cloudFolderIds,
    required Directory stagingDirectory,
  }) async {
    final folders =
        bootstrap.folders
            .where((folder) => cloudFolderIds.contains(folder.id))
            .map(
              (folder) => NotebookFolder(
                id: folder.id,
                name: folder.name,
                createdAt: folder.createdAt,
                updatedAt: folder.updatedAt,
              ),
            )
            .toList()
          ..sort((left, right) => left.id.compareTo(right.id));
    final notebooks = <Notebook>[];
    var assetCount = 0;

    for (final snapshot in bootstrap.notebooks.where(
      (notebook) => cloudNotebookIds.contains(notebook.id),
    )) {
      final pages =
          bootstrap.pages
              .where((page) => page.notebookId == snapshot.id)
              .toList()
            ..sort((left, right) {
              final position = left.position.compareTo(right.position);
              return position != 0 ? position : left.id.compareTo(right.id);
            });
      if (pages.map((page) => page.position).toSet().length != pages.length) {
        throw const FormatException(
          'A bootstrap notebook contains duplicate page positions.',
        );
      }
      final canvases = bootstrap.infiniteCanvases
          .where((canvas) => canvas.notebookId == snapshot.id)
          .toList();
      if (canvases.length > 1) {
        throw const FormatException(
          'A bootstrap notebook contains multiple infinite canvases.',
        );
      }

      final notebookJson = <String, Object?>{
        ...snapshot.content,
        'id': snapshot.id,
        'title': snapshot.title,
        'createdAt': snapshot.createdAt.toIso8601String(),
        'updatedAt': snapshot.updatedAt.toIso8601String(),
        'pageIds': pages.map((page) => page.id).toList(),
        'isArchived': snapshot.isArchived,
        if (snapshot.folderId != null) 'folderId': snapshot.folderId,
        'layoutMode': snapshot.layoutMode,
      };
      final notebook = Notebook.fromJson(notebookJson);
      notebooks.add(notebook);

      final notebookDirectory = Directory(
        '${stagingDirectory.path}/notebooks/${snapshot.id}',
      );
      await notebookDirectory.create(recursive: true);
      for (final page in pages) {
        final pageJson = <String, Object?>{
          ...page.content,
          'id': page.id,
          'width': page.width,
          'height': page.height,
          'coordinateSpaceVersion': page.coordinateSpaceVersion,
          'rotationQuarterTurns': page.rotationQuarterTurns,
          'template': page.template,
        };
        NotePage.fromJson(pageJson);
        await _writeJson(
          File('${notebookDirectory.path}/pages/${page.id}.json'),
          pageJson,
        );
      }
      if (canvases.isNotEmpty) {
        final canvas = canvases.single;
        final canvasJson = <String, Object?>{
          ...canvas.content,
          'background': canvas.background,
        };
        InfiniteCanvasDocument.fromJson(canvasJson);
        await _writeJson(
          File('${notebookDirectory.path}/canvas.json'),
          canvasJson,
        );
      }

      for (final asset in bootstrap.assets.where(
        (asset) => asset.notebookId == snapshot.id,
      )) {
        final download = await assetClient.createAssetDownload(asset.id);
        download.verifyMatches(asset);
        final destination = File(
          '${notebookDirectory.path}/${asset.relativePath}',
        );
        await assetClient.downloadAssetToFile(download, destination);
        await _verifyAsset(asset, destination);
        assetCount++;
      }
    }
    notebooks.sort((left, right) => left.id.compareTo(right.id));
    return _StagedBootstrap(
      directory: stagingDirectory,
      folders: folders,
      notebooks: notebooks,
      assetCount: assetCount,
    );
  }

  Future<void> _verifyAsset(CloudSyncAsset asset, File file) async {
    if (!await file.exists()) {
      throw BootstrapAssetVerificationException(
        asset.id,
        'Downloaded asset is missing from temporary storage.',
      );
    }
    final byteSize = await file.length();
    if (byteSize != asset.byteSize) {
      throw BootstrapAssetVerificationException(
        asset.id,
        'Downloaded asset size does not match bootstrap metadata.',
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != asset.sha256) {
      throw BootstrapAssetVerificationException(
        asset.id,
        'Downloaded asset SHA-256 does not match bootstrap metadata.',
      );
    }
  }

  Future<void> _apply(_StagedBootstrap staged) async {
    await _notebooksDirectory.create(recursive: true);
    final indexFile = File('${_notebooksDirectory.path}/index.json');
    final foldersFile = File('${_notebooksDirectory.path}/folders.json');
    final previousIndex = await _readOptionalBytes(indexFile);
    final previousFolders = await _readOptionalBytes(foldersFile);
    final currentNotebooks = _decodeNotebooks(previousIndex);
    final currentFolders = _decodeFolders(previousFolders);
    final currentNotebookIds = currentNotebooks.map((item) => item.id).toSet();
    final currentFolderIds = currentFolders.map((item) => item.id).toSet();

    if (staged.notebooks.any(
          (notebook) => currentNotebookIds.contains(notebook.id),
        ) ||
        staged.folders.any((folder) => currentFolderIds.contains(folder.id))) {
      throw BootstrapAtomicApplyException(
        'A cloud-only stable ID appeared locally before bootstrap apply.',
      );
    }

    final movedDirectories = <Directory>[];
    try {
      for (final notebook in staged.notebooks) {
        final source = Directory(
          '${staged.directory.path}/notebooks/${notebook.id}',
        );
        final destination = Directory(
          '${_notebooksDirectory.path}/${notebook.id}',
        );
        if (await destination.exists()) {
          throw BootstrapAtomicApplyException(
            'A notebook directory appeared before bootstrap apply.',
          );
        }
        await source.rename(destination.path);
        movedDirectories.add(destination);
      }
      await checkpoint?.call('directoriesMoved');

      await _replaceJson(
        foldersFile,
        [
          ...currentFolders,
          ...staged.folders,
        ].map((folder) => folder.toJson()).toList(),
      );
      await checkpoint?.call('foldersWritten');
      await _replaceJson(
        indexFile,
        [
          ...currentNotebooks,
          ...staged.notebooks,
        ].map((notebook) => notebook.toJson()).toList(),
      );
      await checkpoint?.call('indexWritten');
    } on Object {
      await _restoreFile(foldersFile, previousFolders);
      await _restoreFile(indexFile, previousIndex);
      for (final directory in movedDirectories.reversed) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
      rethrow;
    }
  }

  List<Notebook> _decodeNotebooks(List<int>? bytes) {
    if (bytes == null) {
      return [];
    }
    final value = jsonDecode(utf8.decode(bytes));
    return (value as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(Notebook.fromJson)
        .toList();
  }

  List<NotebookFolder> _decodeFolders(List<int>? bytes) {
    if (bytes == null) {
      return [];
    }
    final value = jsonDecode(utf8.decode(bytes));
    return (value as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(NotebookFolder.fromJson)
        .toList();
  }

  Future<List<int>?> _readOptionalBytes(File file) async {
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> _restoreFile(File file, List<int>? bytes) async {
    if (bytes == null) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await _replaceBytes(file, bytes);
  }

  Future<void> _writeJson(File file, Object? value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  Future<void> _replaceJson(File file, Object? value) {
    return _replaceBytes(
      file,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
    );
  }

  Future<void> _replaceBytes(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.bootstrap-${_stagingId()}');
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temporary.rename(file.path);
    }
  }

  String _stagingId() {
    final entropy = List.generate(
      2,
      (_) => _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '${_clock().toUtc().microsecondsSinceEpoch}-$entropy';
  }
}

class _StagedBootstrap {
  const _StagedBootstrap({
    required this.directory,
    required this.folders,
    required this.notebooks,
    required this.assetCount,
  });

  final Directory directory;
  final List<NotebookFolder> folders;
  final List<Notebook> notebooks;
  final int assetCount;
}
