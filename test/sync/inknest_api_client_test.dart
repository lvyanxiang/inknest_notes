import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_config.dart';

void main() {
  test(
    'login sends the FastAPI contract and parses its token session',
    () async {
      late http.Request captured;
      final client = InkNestApiClient(
        config: InkNestApiConfig.fromEnvironment(
          overrideBaseUrl: 'http://127.0.0.1:8000',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_authJson()), 200);
        }),
      );

      final session = await client.login(
        email: 'user@example.com',
        password: 'password-123',
        deviceName: 'Test iPad',
        platform: 'ios',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'http://127.0.0.1:8000/api/v1/auth/login',
      );
      expect(jsonDecode(captured.body), {
        'email': 'user@example.com',
        'password': 'password-123',
        'deviceName': 'Test iPad',
        'platform': 'ios',
      });
      expect(session.accessToken, 'access-token-value');
      expect(session.user.id, 'user-1');
      expect(session.device.id, 'device-1');
      expect(session.device.current, isTrue);
    },
  );

  test(
    'bootstrap sends bearer auth and parses every current resource',
    () async {
      late http.Request captured;
      final client = InkNestApiClient(
        config: InkNestApiConfig.fromEnvironment(
          overrideBaseUrl: 'https://api.example.com',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_bootstrapJson()), 200);
        }),
      );

      final bootstrap = await client.bootstrap(
        accessToken: 'access-token-value',
      );

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
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
      expect(bootstrap.baseCursor, 'opaque-bootstrap-cursor');
    },
  );

  test('structured FastAPI errors become body-safe API exceptions', () async {
    final client = InkNestApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid email or password.',
              'details': {'attempt': 1},
            },
          }),
          401,
        ),
      ),
    );

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

Map<String, Object?> _authJson() {
  const timestamp = '2026-08-06T00:00:00Z';
  return {
    'accessToken': 'access-token-value',
    'refreshToken': 'refresh-token-value-that-is-long-enough',
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
