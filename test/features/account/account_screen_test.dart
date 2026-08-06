import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

void main() {
  testWidgets('library stays available and sign in updates the Account entry', (
    tester,
  ) async {
    final service = _FakeAuthService();
    final controller = AuthController(
      service: service,
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    expect(find.byTooltip('Sign in'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to InkNest'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'password-123',
    );
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(service.loginCount, 1);
    expect(service.lastDeviceName, 'Test iPad');
    expect(find.text('My Library'), findsOneWidget);
    expect(find.byTooltip('Account: user@example.com'), findsOneWidget);
  });

  testWidgets(
    'registration validates confirmation before calling the service',
    (tester) async {
      final service = _FakeAuthService();
      final controller = AuthController(
        service: service,
        deviceName: 'Test iPad',
        platform: 'ios',
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => InkNestApp(
                        notebookRepository: InMemoryNotebookRepository(),
                        authController: controller,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        'new@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'password-123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password-confirmation')),
        'different-password',
      );
      final submit = find.byKey(const ValueKey('account-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(service.registerCount, 0);
    },
  );

  testWidgets('sign out keeps the library and local notebook intact', (
    tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    await repository.createNotebook(title: 'Local notes');
    final service = _FakeAuthService(restoredSession: _session());
    final controller = AuthController(
      service: service,
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await tester.pumpWidget(
      InkNestApp(notebookRepository: repository, authController: controller),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account: user@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-sign-out')));
    await tester.pumpAndSettle();

    expect(service.logoutCount, 1);
    expect(find.text('Sign in to InkNest'), findsOneWidget);
    expect((await repository.listNotebooks()).single.title, 'Local notes');
  });

  testWidgets('safe authentication error stays on the form', (tester) async {
    final service = _FakeAuthService(loginError: _invalidCredentials());
    final controller = AuthController(
      service: service,
      deviceName: 'Test iPad',
      platform: 'ios',
    );
    await tester.pumpWidget(
      InkNestApp(
        notebookRepository: InMemoryNotebookRepository(),
        authController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('Invalid email or password.'), findsNothing);
    expect(find.text('Sign in to InkNest'), findsOneWidget);
  });

  testWidgets(
    'account form remains accessible at compact width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = AuthController(
        service: _FakeAuthService(),
        deviceName: 'Test iPad',
        platform: 'ios',
      );
      await tester.pumpWidget(
        InkNestApp(
          notebookRepository: InMemoryNotebookRepository(),
          authController: controller,
        ),
      );
      await tester.pumpAndSettle();

      final accountButton = find.byTooltip('Sign in');
      expect(
        tester.getSize(accountButton).shortestSide,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(accountButton);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show password'), findsOneWidget);
      final submit = find.byKey(const ValueKey('account-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({this.restoredSession, this.loginError});

  final InkNestAuthSession? restoredSession;
  final Object? loginError;
  int loginCount = 0;
  int registerCount = 0;
  int logoutCount = 0;
  String? lastDeviceName;

  @override
  Future<InkNestAuthSession?> restoreSession() async => restoredSession;

  @override
  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    loginCount++;
    lastDeviceName = deviceName;
    if (loginError case final error?) {
      throw error;
    }
    return _session(email: email);
  }

  @override
  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    registerCount++;
    return _session(email: email);
  }

  @override
  Future<void> logout() async {
    logoutCount++;
  }
}

InkNestAuthSession _session({String email = 'user@example.com'}) {
  final timestamp = DateTime.utc(2026, 8, 6);
  return InkNestAuthSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token-value-long-enough',
    tokenType: 'bearer',
    expiresIn: 900,
    user: InkNestCloudUser(id: 'user-1', email: email, createdAt: timestamp),
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

InkNestApiException _invalidCredentials() {
  return const InkNestApiException(
    statusCode: 401,
    code: 'invalid_credentials',
    message: 'Invalid email or password.',
    details: {},
  );
}
