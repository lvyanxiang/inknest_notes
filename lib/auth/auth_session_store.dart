import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

class StoredAuthSession {
  const StoredAuthSession({required this.session, required this.expiresAt});

  final InkNestAuthSession session;
  final DateTime expiresAt;

  factory StoredAuthSession.fromSession(
    InkNestAuthSession session, {
    required DateTime issuedAt,
  }) {
    return StoredAuthSession(
      session: session,
      expiresAt: issuedAt.toUtc().add(Duration(seconds: session.expiresIn)),
    );
  }

  factory StoredAuthSession.fromJson(Map<String, Object?> json) {
    final expiresAtValue = json['expiresAt'];
    final expiresAt = expiresAtValue is String
        ? DateTime.tryParse(expiresAtValue)
        : null;
    final sessionValue = json['session'];
    if (expiresAt == null || sessionValue is! Map<Object?, Object?>) {
      throw const FormatException('Stored authentication session is invalid.');
    }
    return StoredAuthSession(
      session: InkNestAuthSession.fromJson(
        sessionValue.cast<String, Object?>(),
      ),
      expiresAt: expiresAt.toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
    'session': session.toJson(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

abstract interface class AuthSessionStore {
  Future<StoredAuthSession?> read();

  Future<void> write(StoredAuthSession session);

  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'inknest.auth.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredAuthSession?> read() async {
    final value = await _storage.read(key: _sessionKey);
    if (value == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException('Stored session must be an object.');
      }
      return StoredAuthSession.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredAuthSession session) {
    return _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}

class MemoryAuthSessionStore implements AuthSessionStore {
  MemoryAuthSessionStore([this.value]);

  StoredAuthSession? value;

  @override
  Future<StoredAuthSession?> read() async => value;

  @override
  Future<void> write(StoredAuthSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
