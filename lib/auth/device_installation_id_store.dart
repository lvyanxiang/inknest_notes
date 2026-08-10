import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DeviceInstallationIdStore {
  Future<String> getOrCreate();
}

class SecureDeviceInstallationIdStore implements DeviceInstallationIdStore {
  SecureDeviceInstallationIdStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'inknest.device.installation-id.v1';

  final FlutterSecureStorage _storage;
  String? _cached;
  Future<String>? _pending;

  @override
  Future<String> getOrCreate() {
    final cached = _cached;
    if (cached != null) {
      return Future.value(cached);
    }
    return _pending ??= _readOrCreate().whenComplete(() => _pending = null);
  }

  Future<String> _readOrCreate() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null && _uuidPattern.hasMatch(stored)) {
      return _cached = stored;
    }
    final created = _uuidV4();
    await _storage.write(key: _storageKey, value: created);
    return _cached = created;
  }
}

class MemoryDeviceInstallationIdStore implements DeviceInstallationIdStore {
  MemoryDeviceInstallationIdStore([String? value]) : _value = value;

  String? _value;

  @override
  Future<String> getOrCreate() async => _value ??= _uuidV4();
}

String _uuidV4() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
