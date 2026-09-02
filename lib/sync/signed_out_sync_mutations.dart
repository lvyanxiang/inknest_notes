import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/sync/sync_resource_map_store.dart';

enum SignedOutSyncMutationKind { upsert, delete }

class SignedOutSyncScope {
  const SignedOutSyncScope({required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;

  String get key => '$userId\u0000$deviceId';

  Map<String, Object?> toJson() => {'userId': userId, 'deviceId': deviceId};

  factory SignedOutSyncScope.fromJson(Map<String, Object?> json) {
    final userId = json['userId'];
    final deviceId = json['deviceId'];
    if (userId is! String ||
        userId.isEmpty ||
        userId.contains('/') ||
        deviceId is! String ||
        deviceId.isEmpty ||
        deviceId.contains('/')) {
      throw const FormatException('Invalid signed-out sync scope.');
    }
    return SignedOutSyncScope(userId: userId, deviceId: deviceId);
  }
}

class SignedOutSyncMutation {
  const SignedOutSyncMutation({
    required this.localKey,
    required this.kind,
    required this.scopes,
  });

  final String localKey;
  final SignedOutSyncMutationKind kind;
  final List<SignedOutSyncScope> scopes;

  Map<String, Object?> toJson() => {
    'localKey': localKey,
    'kind': kind.name,
    'scopes': scopes.map((scope) => scope.toJson()).toList(),
  };

  factory SignedOutSyncMutation.fromJson(Map<String, Object?> json) {
    final localKey = json['localKey'];
    final kindName = json['kind'];
    final rawScopes = json['scopes'];
    if (localKey is! String ||
        localKey.isEmpty ||
        kindName is! String ||
        rawScopes is! List<Object?> ||
        rawScopes.any((scope) => scope is! Map<Object?, Object?>)) {
      throw const FormatException('Invalid signed-out sync mutation.');
    }
    final kind = SignedOutSyncMutationKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('Invalid signed-out sync mutation kind.');
    }
    final scopes = rawScopes
        .map(
          (scope) => SignedOutSyncScope.fromJson(
            (scope! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
    if (scopes.isEmpty ||
        scopes.map((scope) => scope.key).toSet().length != scopes.length) {
      throw const FormatException('Invalid signed-out sync mutation scopes.');
    }
    return SignedOutSyncMutation(
      localKey: localKey,
      kind: kind,
      scopes: List.unmodifiable(scopes),
    );
  }
}

class FileSignedOutSyncMutationStore {
  FileSignedOutSyncMutationStore({required this.rootDirectory})
    : _file = File('${rootDirectory.path}/sync/signed-out-mutations.json');

  static const int currentFormatVersion = 1;

  final Directory rootDirectory;
  final File _file;
  Future<void> _writeQueue = Future.value();
  int _temporaryFileCounter = 0;

  Future<Set<SignedOutSyncScope>> discoverMappedScopes(String localKey) async {
    final syncDirectory = Directory('${rootDirectory.path}/sync');
    if (!await syncDirectory.exists()) return const {};
    final result = <String, SignedOutSyncScope>{};
    await for (final userEntity in syncDirectory.list(followLinks: false)) {
      if (userEntity is! Directory) continue;
      final userId = _basename(userEntity.path);
      await for (final deviceEntity in userEntity.list(followLinks: false)) {
        if (deviceEntity is! Directory) continue;
        final deviceId = _basename(deviceEntity.path);
        try {
          final mapping = await FileSyncResourceMapStore(
            rootDirectory: rootDirectory,
            userId: userId,
            deviceId: deviceId,
          ).find(localKey);
          if (mapping != null) {
            final scope = SignedOutSyncScope(
              userId: userId,
              deviceId: deviceId,
            );
            result[scope.key] = scope;
          }
        } on FileSystemException {
          // A damaged sidecar must never make local note persistence fail.
        } on FormatException {
          // The normal signed-in recovery path will surface invalid sidecars.
        } on TypeError {
          // Treat structurally invalid JSON like another corrupt sidecar.
        }
      }
    }
    return Set.unmodifiable(result.values);
  }

  Future<void> record({
    required String localKey,
    required SignedOutSyncMutationKind kind,
    required Iterable<SignedOutSyncScope> scopes,
  }) {
    final normalizedScopes = {for (final scope in scopes) scope.key: scope};
    if (normalizedScopes.isEmpty) return Future.value();
    return _mutate((mutations) {
      final index = mutations.indexWhere(
        (mutation) => mutation.localKey == localKey,
      );
      if (index == -1) {
        mutations.add(
          SignedOutSyncMutation(
            localKey: localKey,
            kind: kind,
            scopes: List.unmodifiable(normalizedScopes.values),
          ),
        );
        return;
      }
      final existing = mutations[index];
      final mergedScopes = {
        for (final scope in existing.scopes) scope.key: scope,
        ...normalizedScopes,
      };
      mutations[index] = SignedOutSyncMutation(
        localKey: localKey,
        kind: kind,
        scopes: List.unmodifiable(mergedScopes.values),
      );
    });
  }

  Future<List<SignedOutSyncMutation>> loadForScope({
    required String userId,
    required String deviceId,
  }) async {
    await _writeQueue.catchError((_) {});
    final scopeKey = SignedOutSyncScope(userId: userId, deviceId: deviceId).key;
    return List.unmodifiable(
      (await _read()).where(
        (mutation) => mutation.scopes.any((scope) => scope.key == scopeKey),
      ),
    );
  }

  Future<void> consume({
    required String localKey,
    required String userId,
    required String deviceId,
  }) {
    final scopeKey = SignedOutSyncScope(userId: userId, deviceId: deviceId).key;
    return _mutate((mutations) {
      final index = mutations.indexWhere(
        (mutation) => mutation.localKey == localKey,
      );
      if (index == -1) return;
      final existing = mutations[index];
      final remainingScopes = existing.scopes
          .where((scope) => scope.key != scopeKey)
          .toList();
      if (remainingScopes.isEmpty) {
        mutations.removeAt(index);
      } else {
        mutations[index] = SignedOutSyncMutation(
          localKey: existing.localKey,
          kind: existing.kind,
          scopes: List.unmodifiable(remainingScopes),
        );
      }
    });
  }

  Future<void> _mutate(void Function(List<SignedOutSyncMutation>) action) {
    final previous = _writeQueue;
    final next = previous.catchError((_) {}).then((_) async {
      final mutations = await _read();
      action(mutations);
      await _write(mutations);
    });
    _writeQueue = next;
    return next;
  }

  Future<List<SignedOutSyncMutation>> _read() async {
    if (!await _file.exists()) return [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['formatVersion'] != currentFormatVersion ||
        decoded['mutations'] is! List<Object?>) {
      throw const FormatException('Invalid signed-out sync mutation store.');
    }
    final rawMutations = decoded['mutations']! as List<Object?>;
    if (rawMutations.any((mutation) => mutation is! Map<Object?, Object?>)) {
      throw const FormatException('Invalid signed-out sync mutation store.');
    }
    final mutations = rawMutations
        .map(
          (mutation) => SignedOutSyncMutation.fromJson(
            (mutation! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList();
    if (mutations.map((mutation) => mutation.localKey).toSet().length !=
        mutations.length) {
      throw const FormatException('Duplicate signed-out sync mutation.');
    }
    return mutations;
  }

  Future<void> _write(List<SignedOutSyncMutation> mutations) async {
    if (mutations.isEmpty) {
      if (await _file.exists()) await _file.delete();
      return;
    }
    await _file.parent.create(recursive: true);
    final sorted = mutations.toList()
      ..sort((left, right) => left.localKey.compareTo(right.localKey));
    final temporary = File('${_file.path}.tmp-${_temporaryFileCounter++}');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': currentFormatVersion,
        'mutations': sorted.map((mutation) => mutation.toJson()).toList(),
      }),
      flush: true,
    );
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
