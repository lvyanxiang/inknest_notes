import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/auth/device_installation_id_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

enum AuthStatus { restoring, signedOut, submitting, signedIn }

class AuthController extends ChangeNotifier {
  AuthController({
    required this._service,
    required this.deviceName,
    required this.platform,
    DeviceInstallationIdStore? deviceInstallationIdStore,
  }) : _deviceInstallationIdStore =
           deviceInstallationIdStore ?? MemoryDeviceInstallationIdStore() {
    final service = _service;
    if (service case AuthSessionInvalidationSource source) {
      _invalidationSubscription = source.sessionInvalidations.listen((_) {
        _session = null;
        _status = AuthStatus.signedOut;
        _errorMessage = 'Your session has expired. Please sign in again.';
        notifyListeners();
      });
    }
  }

  final AuthService _service;
  final DeviceInstallationIdStore _deviceInstallationIdStore;
  final String deviceName;
  final String platform;

  AuthStatus _status = AuthStatus.restoring;
  InkNestAuthSession? _session;
  String? _errorMessage;
  StreamSubscription<void>? _invalidationSubscription;

  AuthStatus get status => _status;
  InkNestAuthSession? get session => _session;
  String? get errorMessage => _errorMessage;
  bool get isSignedIn => _session != null;
  bool get isBusy => _status == AuthStatus.submitting;

  Future<void> initialize() async {
    try {
      _session = await _service.restoreSession();
      _status = _session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    } on Object {
      _session = null;
      _status = AuthStatus.signedOut;
      _errorMessage = 'Account storage is unavailable on this device.';
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    final clientInstanceId = await _deviceInstallationIdStore.getOrCreate();
    return _authenticate(
      () => _service.login(
        email: email.trim(),
        password: password,
        deviceName: deviceName,
        platform: platform,
        clientInstanceId: clientInstanceId,
      ),
    );
  }

  Future<bool> register({
    required String email,
    required String password,
  }) async {
    final clientInstanceId = await _deviceInstallationIdStore.getOrCreate();
    return _authenticate(
      () => _service.register(
        email: email.trim(),
        password: password,
        deviceName: deviceName,
        platform: platform,
        clientInstanceId: clientInstanceId,
      ),
    );
  }

  Future<bool> _authenticate(
    Future<InkNestAuthSession> Function() action,
  ) async {
    if (isBusy) {
      return false;
    }
    _status = AuthStatus.submitting;
    _errorMessage = null;
    notifyListeners();
    try {
      _session = await action();
      _status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    } on InkNestApiException catch (error) {
      _status = AuthStatus.signedOut;
      _errorMessage = _messageFor(error);
    } on Object {
      _status = AuthStatus.signedOut;
      _errorMessage =
          'Could not reach InkNest Cloud. Check the service and retry.';
    }
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    if (isBusy) {
      return;
    }
    _status = AuthStatus.submitting;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service.logout();
    } on Object {
      _errorMessage =
          'Signed out on this device. Server revocation will need another sign-in.';
    } finally {
      _session = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _invalidationSubscription?.cancel();
    super.dispose();
  }

  static String _messageFor(InkNestApiException error) {
    return switch (error.code) {
      'invalid_credentials' => 'Email or password is incorrect.',
      'email_already_registered' =>
        'An account already exists for this email address.',
      'login_rate_limited' => 'Too many attempts. Please wait and try again.',
      'session_required' || 'invalid_refresh_token' || 'refresh_token_reused' =>
        'Your session has expired. Please sign in again.',
      _ when error.statusCode >= 500 =>
        'InkNest Cloud is temporarily unavailable. Please retry.',
      _ => 'The request could not be completed. Please check your details.',
    };
  }
}

({String name, String platform}) defaultInkNestDeviceIdentity() {
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
  final label = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'InkNest iOS',
    TargetPlatform.android => 'InkNest Android',
    TargetPlatform.macOS => 'InkNest macOS',
    TargetPlatform.windows => 'InkNest Windows',
    TargetPlatform.linux => 'InkNest Linux',
    TargetPlatform.fuchsia => 'InkNest device',
  };
  return (name: label, platform: platform);
}
