import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/config/app_config.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

void main() {
  test(
    'login sends the FastAPI contract and securely stores its session',
    () async {
      late RequestOptions captured;
      final dio = Dio();
      final store = MemoryAuthSessionStore();
      final client = InkNestApiClient(
        config: AppConfig.fromEnvironment(
          overrideApiBaseUrl: 'http://127.0.0.1:8000',
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
        config: AppConfig.fromEnvironment(
          overrideApiBaseUrl: 'https://api.example.com',
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

  test('changes downloads one authenticated cursor page', () async {
    late RequestOptions captured;
    final dio = Dio();
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(_authJson()),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    final client = InkNestApiClient(
      config: AppConfig.fromEnvironment(
        overrideApiBaseUrl: 'https://api.example.com',
      ),
      dio: dio,
      refreshDio: Dio(),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 1),
    );
    _resolveRequests(dio, (options) {
      captured = options;
      return (
        status: 200,
        data: {
          'changes': [
            {
              'changeId': '11111111-1111-4111-8111-111111111111',
              'resourceType': 'page',
              'resourceId': 'page-1',
              'operation': 'upsert',
              'revision': 2,
              'contentHash': 'a' * 64,
              'payload': {
                'id': 'page-1',
                'notebookId': 'notebook-1',
                'content': <String, Object?>{'strokes': <Object?>[]},
              },
              'deviceId': 'device-2',
              'createdAt': '2026-08-06T00:00:00Z',
            },
          ],
          'nextCursor': 'cursor-2',
          'hasMore': true,
        },
      );
    });

    final page = await client.listChanges(cursor: 'cursor-1', limit: 25);

    expect(captured.method, 'GET');
    expect(
      captured.uri.toString(),
      'https://api.example.com/api/v1/sync/changes?cursor=cursor-1&limit=25',
    );
    expect(captured.headers['Authorization'], 'Bearer access-token-value');
    expect(page.changes.single.resourceType, CloudSyncChangeResourceType.page);
    expect(page.changes.single.revision, 2);
    expect(page.nextCursor, 'cursor-2');
    expect(page.hasMore, isTrue);
  });

  test(
    'conflict resolution posts the selected outcome and parses response',
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
        config: AppConfig.fromEnvironment(
          overrideApiBaseUrl: 'https://api.example.com',
        ),
        dio: dio,
        refreshDio: Dio(),
        sessionStore: store,
        clock: () => DateTime.utc(2026, 8, 6, 0, 1),
      );
      _resolveRequests(dio, (options) {
        captured = options;
        return (status: 200, data: _resolvedConflictJson());
      });

      final conflict = await client.resolveSyncConflict(
        conflictId: '11111111-1111-4111-8111-111111111111',
        resolution: SyncConflictResolution.keepBoth,
      );

      expect(captured.method, 'POST');
      expect(
        captured.uri.toString(),
        'https://api.example.com/api/v1/sync/conflicts/'
        '11111111-1111-4111-8111-111111111111/resolve',
      );
      expect(captured.data, {'resolution': 'keep_both'});
      expect(conflict.originalResourceId, 'page-1');
      expect(conflict.resolution, 'keep_both');
      expect(conflict.isPending, isFalse);
    },
  );

  test(
    'Tombstone restore posts the selected record and parses response',
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
        config: AppConfig.fromEnvironment(
          overrideApiBaseUrl: 'https://api.example.com',
        ),
        dio: dio,
        refreshDio: Dio(),
        sessionStore: store,
        clock: () => DateTime.utc(2026, 8, 6, 0, 1),
      );
      _resolveRequests(dio, (options) {
        captured = options;
        return (status: 200, data: _restoredTombstoneJson());
      });

      final tombstone = await client.restoreSyncTombstone(
        '11111111-1111-4111-8111-111111111111',
      );

      expect(captured.method, 'POST');
      expect(
        captured.uri.toString(),
        'https://api.example.com/api/v1/sync/tombstones/'
        '11111111-1111-4111-8111-111111111111/restore',
      );
      expect(captured.data, isEmpty);
      expect(tombstone.resourceId, 'notebook-1');
      expect(tombstone.state, 'restored');
      expect(tombstone.resolution, 'restored_snapshot');
    },
  );

  test('shared-content commit uses the incremental sync contract', () async {
    late RequestOptions captured;
    final dio = Dio();
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(_authJson()),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    final client = InkNestApiClient(
      config: AppConfig.fromEnvironment(
        overrideApiBaseUrl: 'https://api.example.com',
      ),
      dio: dio,
      refreshDio: Dio(),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 1),
    );
    _resolveRequests(dio, (options) {
      captured = options;
      return (
        status: 200,
        data: {
          'idempotencyKey': 'reconcile-1',
          'replayed': false,
          'results': [
            {
              'operationId': 'operation-1',
              'resourceType': 'page',
              'resourceId': 'page-1',
              'revision': 2,
              'contentHash': 'a' * 64,
              'changed': false,
              'outcome': 'conflict',
              'conflict': <String, Object?>{},
              'tombstone': null,
            },
          ],
          'nextCursor': 'cursor-2',
        },
      );
    });
    final operations = [
      {
        'operationId': 'operation-1',
        'operation': 'upsert',
        'resourceType': 'page',
        'resourceId': 'page-1',
        'baseRevision': 0,
        'content': <String, Object?>{'strokes': <Object?>[]},
      },
    ];

    final result = await client.commitSharedContent(
      deviceId: 'device-1',
      idempotencyKey: 'reconcile-1',
      baseCursor: 'cursor-1',
      operations: operations,
    );

    expect(captured.method, 'POST');
    expect(
      captured.uri.toString(),
      'https://api.example.com/api/v1/sync/commit',
    );
    expect(captured.data, {
      'deviceId': 'device-1',
      'idempotencyKey': 'reconcile-1',
      'baseCursor': 'cursor-1',
      'operations': operations,
    });
    expect(result.results.single.outcome, 'conflict');
    expect(result.nextCursor, 'cursor-2');
  });

  test(
    'asset download URL is authenticated but signed object GET is not',
    () async {
      final dio = Dio();
      final transferDio = Dio();
      final store = MemoryAuthSessionStore(
        StoredAuthSession.fromSession(
          InkNestAuthSession.fromJson(_authJson()),
          issuedAt: DateTime.utc(2026, 8, 6),
        ),
      );
      final client = InkNestApiClient(
        config: AppConfig.fromEnvironment(
          overrideApiBaseUrl: 'https://api.example.com',
        ),
        dio: dio,
        refreshDio: transferDio,
        sessionStore: store,
        clock: () => DateTime.utc(2026, 8, 6, 0, 1),
      );
      late RequestOptions descriptorRequest;
      late RequestOptions objectRequest;
      _resolveRequests(dio, (options) {
        descriptorRequest = options;
        return (
          status: 200,
          data: {
            'assetId': 'asset-1',
            'filename': 'notes.pdf',
            'relativePath': 'assets/imported.pdf',
            'contentType': 'application/pdf',
            'byteSize': 4,
            'sha256': 'c' * 64,
            'downloadUrl': 'https://objects.example.com/signed-object?secret=x',
            'method': 'GET',
            'expiresAt': '2026-08-06T00:05:00Z',
          },
        );
      });
      transferDio.httpClientAdapter = _BytesAdapter((options) {
        objectRequest = options;
        return [1, 2, 3, 4];
      });
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'inknest-api-download-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final download = await client.createAssetDownload('asset-1');
      final destination = File('${temporaryDirectory.path}/asset.pdf');
      await client.downloadAssetToFile(download, destination);

      expect(
        descriptorRequest.uri.toString(),
        'https://api.example.com/api/v1/assets/asset-1/download-url',
      );
      expect(
        descriptorRequest.headers['Authorization'],
        'Bearer access-token-value',
      );
      expect(objectRequest.uri.host, 'objects.example.com');
      expect(objectRequest.headers['Authorization'], isNull);
      expect(await destination.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('initial merge and asset upload use the FastAPI contracts', () async {
    final dio = Dio();
    final transferDio = Dio();
    final store = MemoryAuthSessionStore(
      StoredAuthSession.fromSession(
        InkNestAuthSession.fromJson(_authJson()),
        issuedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    final client = InkNestApiClient(
      config: AppConfig.fromEnvironment(
        overrideApiBaseUrl: 'https://api.example.com',
      ),
      dio: dio,
      refreshDio: transferDio,
      sessionStore: store,
      clock: () => DateTime.utc(2026, 8, 6, 0, 1),
    );
    final paths = <String>[];
    _resolveRequests(dio, (options) {
      paths.add(options.uri.path);
      if (options.uri.path.endsWith('/sync/merge/commit')) {
        return (
          status: 200,
          data: {
            'idempotencyKey': 'batch-1',
            'replayed': false,
            'results': <Object?>[],
            'nextCursor': 'cursor-2',
          },
        );
      }
      if (options.uri.path.endsWith('/assets/upload-sessions')) {
        return (
          status: 201,
          data: {
            'uploadId': 'upload-1',
            'assetId': 'asset-1',
            'status': 'pending',
            'objectKey': 'staging/key',
            'uploadUrl': 'https://objects.example.com/signed-upload',
            'method': 'PUT',
            'requiredHeaders': {'Content-Type': 'image/png'},
            'uploadUrlExpiresAt': '2026-08-06T00:05:00Z',
            'sessionExpiresAt': '2026-08-06T01:00:00Z',
          },
        );
      }
      return (status: 200, data: {'assetId': 'asset-1', 'status': 'ready'});
    });
    late RequestOptions uploadRequest;
    transferDio.httpClientAdapter = _BytesAdapter((options) {
      uploadRequest = options;
      return const [];
    });
    final directory = await Directory.systemTemp.createTemp('inknest-upload-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/image.png')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final asset = LocalSyncAsset(
      id: 'asset-1',
      notebookId: 'notebook-1',
      kind: 'image',
      filename: 'image.png',
      relativePath: 'assets/images/image.png',
      contentType: 'image/png',
      byteSize: 4,
      sha256: 'a' * 64,
      file: file,
    );

    final merge = await client.commitInitialMerge(
      deviceId: 'device-1',
      idempotencyKey: 'batch-1',
      baseCursor: 'cursor-1',
      operations: const [],
    );
    final session = await client.createAssetUploadSession(asset);
    await client.uploadAssetFile(session, asset);
    await client.completeAssetUpload(session.uploadId);

    expect(merge.nextCursor, 'cursor-2');
    expect(paths, [
      '/api/v1/sync/merge/commit',
      '/api/v1/assets/upload-sessions',
      '/api/v1/assets/upload-sessions/upload-1/complete',
    ]);
    expect(uploadRequest.method, 'PUT');
    expect(uploadRequest.uri.host, 'objects.example.com');
    expect(uploadRequest.headers['Authorization'], isNull);
    expect(uploadRequest.headers['Content-Type'], 'image/png');
  });

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
      () => AppConfig.fromEnvironment(
        overrideApiBaseUrl: 'http://localhost:8000/api/v1',
      ),
      throwsFormatException,
    );
    expect(
      () => AppConfig.fromEnvironment(overrideApiBaseUrl: 'file:///tmp/api'),
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

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytesFor);

  final List<int> Function(RequestOptions options) bytesFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(bytesFor(options), 200);
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

Map<String, Object?> _resolvedConflictJson() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'resourceType': 'page',
  'originalResourceId': 'page-1',
  'copyResourceId': 'page-copy-1',
  'copyDisplayName': '第 1 页（冲突副本）',
  'baseRevision': 1,
  'currentRevision': 2,
  'submittedContentHash': 'a' * 64,
  'submittedContent': const {'strokes': <Object?>[]},
  'currentContentHash': 'b' * 64,
  'currentContent': const {'strokes': <Object?>[]},
  'sourceDeviceId': '22222222-2222-4222-8222-222222222222',
  'status': 'resolved',
  'resolution': 'keep_both',
  'resolvedByDeviceId': '33333333-3333-4333-8333-333333333333',
  'resolvedAt': '2026-08-07T01:00:00Z',
  'createdAt': '2026-08-07T00:00:00Z',
};

Map<String, Object?> _restoredTombstoneJson() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'resourceType': 'notebook',
  'resourceId': 'notebook-1',
  'baseRevision': 1,
  'resourceRevision': 1,
  'deletedRevision': 2,
  'contentHash': 'a' * 64,
  'content': const {'bookmarkedPageIds': <Object?>[]},
  'deletedByDeviceId': '22222222-2222-4222-8222-222222222222',
  'deletedAt': '2026-08-07T00:00:00Z',
  'state': 'restored',
  'conflictKind': null,
  'resolution': 'restored_snapshot',
  'conflictingDeviceId': null,
  'restoredByDeviceId': '33333333-3333-4333-8333-333333333333',
  'restoredAt': '2026-08-07T01:00:00Z',
  'createdAt': '2026-08-07T00:00:00Z',
};

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
        'revision': 0,
        'contentHash': '',
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
        'relativePath': 'assets/imported.pdf',
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
