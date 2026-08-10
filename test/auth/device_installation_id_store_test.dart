import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/auth/device_installation_id_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installation identity survives logout and store recreation', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = await SecureDeviceInstallationIdStore().getOrCreate();

    await SecureAuthSessionStore().clear();
    final restored = await SecureDeviceInstallationIdStore().getOrCreate();

    expect(restored, first);
    expect(
      restored,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
