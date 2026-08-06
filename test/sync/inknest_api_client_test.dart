import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_config.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';

void main() {
  test(
    'login sends the FastAPI contract and securely stores its session',
    () async {
      late RequestOptions captured;
      final dio = Dio();
      final store = MemoryAuthSessionStore();
      final client = InkNestApiClient(
        config: InkNestApiConfig.fromEnvironment(
          overrideBaseUrl: 'http://127.0.0.1:8000',
        ),
        dio: dio,
        refreshDio: Dio(),
        sessionStore: store,
        clock: () => DateTime.utc(2026, 8, 6),
      );
      _resolveRequests(dio, (options) {
        captured = options;
        return (status: 200, data: _authJson());
      });

      final session = await client.login(
        email: 'user@example.com',
        password: 'password-123',
        deviceName: 'Test iPad',
        platform: 'ios',
      );

      expect(captured.method, 'POST');
      expect(
        captured.uri.toString(),
        'http://127.0.0.1:8000/api/v1/auth/login',
      );
      expect(captured.data, {
        'email': 'user@example.com',
        'password': 'password-123',
        'deviceName': 'Test iPad',
        'platform': 'ios',
      });
      expect(session.accessToken, 'access-token-value');
      expect((await store.read())?.session.user.id, 'user-1');
      expect((await store.read())?.expiresAt, DateTime.utc(2026, 8, 6, 0, 15));
    },
  );

  test(
    'bootstrap attaches the stored access token and parses resources',
    () async {
      late RequestOptions captured;
      final dio = Dio();
      final store = MemoryAuthSessionStore(
        StoredAuthSession.fromSession(
          InkNestAuthSession.fromJson(_authJson()),
          issuedAt: DateTime.utc(2026, 8, 6),
        ),
      );
      final client = InkNestApiClient(
        config: InkNestApiConfig.fromEnvironment(
          overrideBaseUrl: 'https://api.example.com',
        ),
        dio: dio,
        refreshDio: Dio(),
        sessionStore: store,
        clock: () => DateTime.utc(2026, 8, 6, 0, 1),
      );
      _resolveRequests(dio, (options) {
        captured = options;
        return (status: 200, data: _bootstrapJson());
      });

      final bootstrap = await client.bootstrap();

      expect(captured.method, 'GET');
      expect(
        captured.uri.toString(),
        'https://api.example.com/api/v1/sync/bootstrap',
      );
      expect(captured.headers['Authorization'], 'Bearer access-token-value');
      expect(bootstrap.folders.single.id, 'folder-1');
      expect(
        bootstrap.notebooks.map((notebook) => notebook.id),
        containsAll(['notebook-1', 'notebook-2']),
      );
      expect(bootstrap.pages.single.id, 'page-1');
      expect(bootstrap.infiniteCanvases.single.id, 'canvas-1');
      expect(bootstrap.assets.single.id, 'asset-1');
    },
  );

  test('concurrent expired requests share one rotated refresh token', () async {
    final dio = Dio();
    final refreshDio = Dio();
    final expired = _authJson(
      accessToken: 'expired-access-token',
      refreshToken: 'old-refresh-token-that-is-long-enough',
    );
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(expired),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    var refreshCount = 0;
    final authorizedTokens = <Object?>[];
    final client = InkNestApiClient(
      dio: dio,
      refreshDio: refreshDio,
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 20),
    );
    _resolveRequests(refreshDio, (options) {
      refreshCount++;
      expect(options.data, {
        'refreshToken': 'old-refresh-token-that-is-long-enough',
      });
      return (
        status: 200,
        data: _authJson(
          accessToken: 'rotated-access-token',
          refreshToken: 'rotated-refresh-token-that-is-long-enough',
        ),
      );
    });
    _resolveRequests(dio, (options) {
      authorizedTokens.add(options.headers['Authorization']);
      return (status: 200, data: _bootstrapJson());
    });

    await Future.wait([client.bootstrap(), client.bootstrap()]);

    expect(refreshCount, 1);
    expect(authorizedTokens, [
      'Bearer rotated-access-token',
      'Bearer rotated-access-token',
    ]);
    expect(
      (await store.read())?.session.refreshToken,
      'rotated-refresh-token-that-is-long-enough',
    );
  });

  test('a 401 refreshes once and retries the authenticated request', () async {
    final dio = Dio();
    final refreshDio = Dio();
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(_authJson()),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    var requestCount = 0;
    var refreshCount = 0;
    final client = InkNestApiClient(
      dio: dio,
      refreshDio: refreshDio,
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 1),
    );
    _resolveRequests(refreshDio, (_) {
      refreshCount++;
      return (
        status: 200,
        data: _authJson(
          accessToken: 'after-401-access-token',
          refreshToken: 'after-401-refresh-token-that-is-long-enough',
        ),
      );
    });
    _resolveRequests(dio, (options) {
      requestCount++;
      if (requestCount == 1) {
        return (
          status: 401,
          data: {
            'error': {
              'code': 'invalid_access_token',
              'message': 'Expired.',
              'details': <String, Object?>{},
            },
          },
        );
      }
      expect(options.headers['Authorization'], 'Bearer after-401-access-token');
      return (status: 200, data: _bootstrapJson());
    });

    await client.bootstrap();

    expect(requestCount, 2);
    expect(refreshCount, 1);
  });

  test('a rejected refresh clears the session and announces expiry', () async {
    final dio = Dio();
    final refreshDio = Dio();
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(_authJson()),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    final client = InkNestApiClient(
      dio: dio,
      refreshDio: refreshDio,
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 1),
    );
    _resolveRequests(dio, (_) {
      return (
        status: 401,
        data: {
          'error': {
            'code': 'invalid_access_token',
            'message': 'Expired.',
            'details': <String, Object?>{},
          },
        },
      );
    });
    _resolveRequests(refreshDio, (_) {
      return (
        status: 401,
        data: {
          'error': {
            'code': 'invalid_refresh_token',
            'message': 'Expired.',
            'details': <String, Object?>{},
          },
        },
      );
    });
    var invalidationCount = 0;
    final subscription = client.sessionInvalidations.listen(
      (_) => invalidationCount++,
    );

    await expectLater(
      client.bootstrap(),
      throwsA(
        isA<InkNestApiException>().having(
          (error) => error.code,
          'code',
          'invalid_refresh_token',
        ),
      ),
    );

    expect(await store.read(), isNull);
    expect(invalidationCount, 1);
    await subscription.cancel();
  });

  test('structured FastAPI errors become body-safe API exceptions', () async {
    final dio = Dio();
    final client = InkNestApiClient(
      dio: dio,
      refreshDio: Dio(),
      sessionStore: MemoryAuthSessionStore(),
    );
    _resolveRequests(dio, (_) {
      return (
        status: 401,
        data: {
          'error': {
            'code': 'invalid_credentials',
            'message': 'Invalid email or password.',
            'details': {'attempt': 1},
          },
        },
      );
    });

    await expectLater(
      client.login(
        email: 'user@example.com',
        password: 'wrong-password',
        deviceName: 'Test iPad',
        platform: 'ios',
      ),
      throwsA(
        isA<InkNestApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'invalid_credentials')
            .having(
              (error) => error.toString(),
              'safe toString',
              isNot(contains('Invalid email or password')),
            ),
      ),
    );
  });

  test('API base URL rejects paths, queries, and non-HTTP schemes', () {
    expect(
      () => InkNestApiConfig.fromEnvironment(
        overrideBaseUrl: 'http://localhost:8000/api/v1',
      ),
      throwsFormatException,
    );
    expect(
      () =>
          InkNestApiConfig.fromEnvironment(overrideBaseUrl: 'file:///tmp/api'),
      throwsFormatException,
    );
  });
}

typedef _MockResponse = ({int status, Object? data});

void _resolveRequests(
  Dio dio,
  FutureOr<_MockResponse> Function(RequestOptions options) responseFor,
) {
  dio.httpClientAdapter = _CallbackAdapter(responseFor);
}

class _CallbackAdapter implements HttpClientAdapter {
  _CallbackAdapter(this.responseFor);

  final FutureOr<_MockResponse> Function(RequestOptions options) responseFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await responseFor(options);
    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _authJson({
  String accessToken = 'access-token-value',
  String refreshToken = 'refresh-token-value-that-is-long-enough',
}) {
  const timestamp = '2026-08-06T00:00:00Z';
  return {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': 'bearer',
    'expiresIn': 900,
    'user': {
      'id': 'user-1',
      'email': 'user@example.com',
      'createdAt': timestamp,
    },
    'device': {
      'id': 'device-1',
      'name': 'Test iPad',
      'platform': 'ios',
      'createdAt': timestamp,
      'lastSeenAt': timestamp,
      'revokedAt': null,
      'current': true,
    },
  };
}

Map<String, Object?> _bootstrapJson() {
  const timestamp = '2026-08-06T00:00:00Z';
  return {
    'hasCloudLibrary': true,
    'folderIds': ['folder-1'],
    'notebookIds': ['notebook-1', 'notebook-2'],
    'folders': [
      {
        'id': 'folder-1',
        'name': 'Study',
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'notebooks': [
      {
        'id': 'notebook-1',
        'folderId': 'folder-1',
        'title': 'Notes',
        'layoutMode': 'paged',
        'isArchived': false,
        'revision': 0,
        'contentHash': '',
        'content': <String, Object?>{},
        'conflictOf': null,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
      {
        'id': 'notebook-2',
        'folderId': 'folder-1',
        'title': 'Canvas',
        'layoutMode': 'infiniteCanvas',
        'isArchived': false,
        'revision': 0,
        'contentHash': '',
        'content': <String, Object?>{},
        'conflictOf': null,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'pages': [
      {
        'id': 'page-1',
        'notebookId': 'notebook-1',
        'position': 0,
        'width': 768,
        'height': 1024,
        'coordinateSpaceVersion': {'major': 99},
        'rotationQuarterTurns': 0,
        'template': 'blank',
        'revision': 1,
        'contentHash': 'a' * 64,
        'content': {'strokes': <Object?>[]},
        'conflictOf': null,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'infiniteCanvases': [
      {
        'id': 'canvas-1',
        'notebookId': 'notebook-2',
        'background': 'blank',
        'revision': 1,
        'contentHash': 'b' * 64,
        'content': {'nodes': <Object?>[]},
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'assets': [
      {
        'id': 'asset-1',
        'notebookId': 'notebook-1',
        'kind': 'pdf',
        'originalFilename': 'notes.pdf',
        'contentType': 'application/pdf',
        'byteSize': 42,
        'sha256': 'c' * 64,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      },
    ],
    'counts': {
      'folders': 1,
      'notebooks': 2,
      'pages': 1,
      'infiniteCanvases': 1,
      'assets': 1,
    },
    'baseCursor': 'opaque-bootstrap-cursor',
  };
}
