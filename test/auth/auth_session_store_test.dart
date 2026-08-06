import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

void main() {
  test('stored authentication session round-trips tokens and identity', () {
    final stored = StoredAuthSession.fromSession(
      _session(),
      issuedAt: DateTime.utc(2026, 8, 6),
    );

    final restored = StoredAuthSession.fromJson(stored.toJson());

    expect(restored.session.accessToken, 'access-token');
    expect(restored.session.refreshToken, 'refresh-token-value-long-enough');
    expect(restored.session.user.email, 'user@example.com');
    expect(restored.session.device.name, 'Test iPad');
    expect(restored.expiresAt, DateTime.utc(2026, 8, 6, 0, 15));
  });
}

InkNestAuthSession _session() {
  final timestamp = DateTime.utc(2026, 8, 6);
  return InkNestAuthSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token-value-long-enough',
    tokenType: 'bearer',
    expiresIn: 900,
    user: InkNestCloudUser(
      id: 'user-1',
      email: 'user@example.com',
      createdAt: timestamp,
    ),
    device: InkNestCloudDevice(
      id: 'device-1',
      name: 'Test iPad',
      platform: 'ios',
      createdAt: timestamp,
      lastSeenAt: timestamp,
      current: true,
    ),
  );
}
