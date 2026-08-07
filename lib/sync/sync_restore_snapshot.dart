import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class SyncRestoreRollbackException implements Exception {
  const SyncRestoreRollbackException({
    required this.restoreError,
    required this.rollbackError,
  });

  final Object restoreError;
  final Object rollbackError;

  @override
  String toString() =>
      'The sync restore failed and its recovery snapshot could not be '
      'reapplied. Restore error: $restoreError; rollback error: $rollbackError';
}

/// Runs a local sync restore inside a verified recovery boundary.
///
/// The snapshot is deliberately internal and short-lived. It is not the
/// user-facing `.inknestbackup` archive format.
Future<T> withSyncRestoreSnapshot<T>({
  required Directory rootDirectory,
  required String userId,
  required String deviceId,
  required Future<T> Function() action,
}) async {
  _validateScopeSegment(userId, 'userId');
  _validateScopeSegment(deviceId, 'deviceId');
  final snapshot = await _SyncRestoreSnapshot.capture(
    rootDirectory: rootDirectory,
    userId: userId,
    deviceId: deviceId,
  );
  try {
    final result = await action();
    await snapshot.discard();
    return result;
  } catch (error, stackTrace) {
    try {
      await snapshot.rollback();
    } catch (rollbackError) {
      throw SyncRestoreRollbackException(
        restoreError: error,
        rollbackError: rollbackError,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

class _SyncRestoreSnapshot {
  _SyncRestoreSnapshot({
    required this.snapshotDirectory,
    required this.notebooksDirectory,
    required this.deviceDirectory,
    required this.snapshotNotebooksDirectory,
    required this.snapshotDeviceDirectory,
    required this.hadNotebooksDirectory,
    required this.hadDeviceDirectory,
    required this.files,
  });

  static const int _formatVersion = 1;

  final Directory snapshotDirectory;
  final Directory notebooksDirectory;
  final Directory deviceDirectory;
  final Directory snapshotNotebooksDirectory;
  final Directory snapshotDeviceDirectory;
  final bool hadNotebooksDirectory;
  final bool hadDeviceDirectory;
  final List<_SnapshotFile> files;

  static Future<_SyncRestoreSnapshot> capture({
    required Directory rootDirectory,
    required String userId,
    required String deviceId,
  }) async {
    final notebooks = Directory('${rootDirectory.path}/notebooks');
    final device = Directory('${rootDirectory.path}/sync/$userId/$deviceId');
    final recoveryRoot = Directory(
      '${rootDirectory.path}/sync/restore-recovery',
    );
    await recoveryRoot.create(recursive: true);
    final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
    final snapshotDirectory = Directory(
      '${recoveryRoot.path}/${DateTime.now().toUtc().microsecondsSinceEpoch}-$nonce',
    );
    final snapshotNotebooks = Directory('${snapshotDirectory.path}/notebooks');
    final snapshotDevice = Directory('${snapshotDirectory.path}/device');
    final hadNotebooks = await notebooks.exists();
    final hadDevice = await device.exists();

    try {
      await snapshotDirectory.create(recursive: true);
      if (hadNotebooks) {
        await _copyDirectory(notebooks, snapshotNotebooks);
      }
      if (hadDevice) {
        await _copyDirectory(device, snapshotDevice);
      }
      final files = <_SnapshotFile>[
        if (hadNotebooks)
          ...await _inventory(snapshotNotebooks, rootName: 'notebooks'),
        if (hadDevice) ...await _inventory(snapshotDevice, rootName: 'device'),
      ]..sort((left, right) => left.path.compareTo(right.path));
      final manifest = File('${snapshotDirectory.path}/manifest.json');
      await manifest.writeAsString(
        jsonEncode({
          'formatVersion': _formatVersion,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'hadNotebooksDirectory': hadNotebooks,
          'hadDeviceDirectory': hadDevice,
          'files': files.map((item) => item.toJson()).toList(),
        }),
        flush: true,
      );
      final snapshot = _SyncRestoreSnapshot(
        snapshotDirectory: snapshotDirectory,
        notebooksDirectory: notebooks,
        deviceDirectory: device,
        snapshotNotebooksDirectory: snapshotNotebooks,
        snapshotDeviceDirectory: snapshotDevice,
        hadNotebooksDirectory: hadNotebooks,
        hadDeviceDirectory: hadDevice,
        files: files,
      );
      await snapshot._verify();
      return snapshot;
    } catch (_) {
      if (await snapshotDirectory.exists()) {
        await snapshotDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> discard() async {
    if (await snapshotDirectory.exists()) {
      await snapshotDirectory.delete(recursive: true);
    }
    await _deleteEmptyRecoveryRoot();
  }

  Future<void> rollback() async {
    await _verify();
    final replacements = [
      _DirectoryReplacement(
        target: notebooksDirectory,
        snapshot: snapshotNotebooksDirectory,
        existed: hadNotebooksDirectory,
        failed: Directory('${snapshotDirectory.path}/failed-notebooks'),
      ),
      _DirectoryReplacement(
        target: deviceDirectory,
        snapshot: snapshotDeviceDirectory,
        existed: hadDeviceDirectory,
        failed: Directory('${snapshotDirectory.path}/failed-device'),
      ),
    ];
    final applied = <_DirectoryReplacement>[];
    try {
      for (final replacement in replacements) {
        await replacement.apply();
        applied.add(replacement);
      }
    } catch (_) {
      for (final replacement in applied.reversed) {
        await replacement.undo();
      }
      rethrow;
    }
    await discard();
  }

  Future<void> _verify() async {
    final manifest = File('${snapshotDirectory.path}/manifest.json');
    if (!await manifest.exists()) {
      throw const FormatException('Missing sync restore snapshot manifest.');
    }
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['formatVersion'] != _formatVersion ||
        decoded['hadNotebooksDirectory'] != hadNotebooksDirectory ||
        decoded['hadDeviceDirectory'] != hadDeviceDirectory) {
      throw const FormatException('Invalid sync restore snapshot manifest.');
    }
    final manifestFiles = decoded['files'];
    if (manifestFiles is! List<Object?>) {
      throw const FormatException('Invalid sync restore snapshot file list.');
    }
    final recorded = manifestFiles.map(_SnapshotFile.fromJson).toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    if (!_sameFiles(recorded, files)) {
      throw const FormatException('Sync restore snapshot manifest changed.');
    }
    final actual = <_SnapshotFile>[
      if (hadNotebooksDirectory)
        ...await _inventory(snapshotNotebooksDirectory, rootName: 'notebooks'),
      if (hadDeviceDirectory)
        ...await _inventory(snapshotDeviceDirectory, rootName: 'device'),
    ]..sort((left, right) => left.path.compareTo(right.path));
    if (!_sameFiles(actual, files)) {
      throw const FormatException('Sync restore snapshot verification failed.');
    }
  }

  Future<void> _deleteEmptyRecoveryRoot() async {
    final recoveryRoot = snapshotDirectory.parent;
    if (await recoveryRoot.exists() &&
        await recoveryRoot.list(followLinks: false).isEmpty) {
      await recoveryRoot.delete();
    }
  }
}

class _DirectoryReplacement {
  _DirectoryReplacement({
    required this.target,
    required this.snapshot,
    required this.existed,
    required this.failed,
  });

  final Directory target;
  final Directory snapshot;
  final bool existed;
  final Directory failed;
  bool movedCurrent = false;
  bool installedSnapshot = false;

  Future<void> apply() async {
    if (await target.exists()) {
      await failed.parent.create(recursive: true);
      await target.rename(failed.path);
      movedCurrent = true;
    }
    try {
      if (existed) {
        await target.parent.create(recursive: true);
        await snapshot.rename(target.path);
        installedSnapshot = true;
      }
    } catch (_) {
      await undo();
      rethrow;
    }
  }

  Future<void> undo() async {
    if (installedSnapshot && await target.exists()) {
      await target.rename(snapshot.path);
      installedSnapshot = false;
    }
    if (movedCurrent && await failed.exists()) {
      await failed.rename(target.path);
      movedCurrent = false;
    }
  }
}

class _SnapshotFile {
  const _SnapshotFile({
    required this.path,
    required this.byteSize,
    required this.sha256Hash,
  });

  final String path;
  final int byteSize;
  final String sha256Hash;

  factory _SnapshotFile.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Invalid sync restore snapshot file.');
    }
    final path = value['path'];
    final byteSize = value['byteSize'];
    final sha256Hash = value['sha256'];
    if (path is! String ||
        (!path.startsWith('notebooks/') && !path.startsWith('device/')) ||
        byteSize is! int ||
        byteSize < 0 ||
        sha256Hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hash)) {
      throw const FormatException('Invalid sync restore snapshot file.');
    }
    return _SnapshotFile(
      path: path,
      byteSize: byteSize,
      sha256Hash: sha256Hash,
    );
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'byteSize': byteSize,
    'sha256': sha256Hash,
  };

  @override
  bool operator ==(Object other) =>
      other is _SnapshotFile &&
      path == other.path &&
      byteSize == other.byteSize &&
      sha256Hash == other.sha256Hash;

  @override
  int get hashCode => Object.hash(path, byteSize, sha256Hash);
}

bool _sameFiles(List<_SnapshotFile> left, List<_SnapshotFile> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final targetPath = '${destination.path}/$relative';
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await _copyDirectory(Directory(entity.path), Directory(targetPath));
      case FileSystemEntityType.file:
        await File(entity.path).copy(targetPath);
      case FileSystemEntityType.link:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.notFound:
        throw FileSystemException(
          'Unsupported entry in sync restore snapshot.',
          entity.path,
        );
    }
  }
}

Future<List<_SnapshotFile>> _inventory(
  Directory directory, {
  required String rootName,
}) async {
  if (!await directory.exists()) {
    throw FileSystemException('Missing snapshot directory.', directory.path);
  }
  final result = <_SnapshotFile>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) continue;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Unsupported entry in sync restore snapshot.',
        entity.path,
      );
    }
    final file = File(entity.path);
    final relative = entity.path.substring(directory.path.length + 1);
    final digest = await sha256.bind(file.openRead()).first;
    result.add(
      _SnapshotFile(
        path: '$rootName/$relative',
        byteSize: await file.length(),
        sha256Hash: digest.toString(),
      ),
    );
  }
  return result;
}

void _validateScopeSegment(String value, String name) {
  if (value.isEmpty ||
      value.trim() != value ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\')) {
    throw ArgumentError.value(value, name, 'Invalid sync scope segment.');
  }
}
