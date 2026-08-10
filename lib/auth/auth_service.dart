import 'package:inknest_notes/sync/inknest_api_models.dart';

abstract interface class AuthService {
  Future<InkNestAuthSession?> restoreSession();

  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
  });

  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
  });

  Future<void> logout();
}

abstract interface class AuthSessionInvalidationSource {
  Stream<void> get sessionInvalidations;
}
