import 'package:inknest_notes/sync/inknest_api_models.dart';

abstract interface class AuthService {
  Future<InkNestAuthSession?> restoreSession();

  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
    required String privacyPolicyVersion,
    required String termsVersion,
  });

  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
  });

  Future<void> logout();

  Future<InkNestCloudUser> acceptAgreements({
    required String privacyPolicyVersion,
    required String termsVersion,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<AccountDeletionResult> deleteAccount({required String password});
}

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.status,
    required this.cloudDeletionComplete,
    required this.localDataRetained,
  });

  final String status;
  final bool cloudDeletionComplete;
  final bool localDataRetained;
}

abstract interface class AuthSessionInvalidationSource {
  Stream<void> get sessionInvalidations;
}
