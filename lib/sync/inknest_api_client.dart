import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/config/app_config.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_cloud_client.dart';
import 'package:inknest_notes/sync/sync_changes.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';
import 'package:inknest_notes/sync/sync_upload_models.dart';

class InkNestApiException implements Exception {
  const InkNestApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'InkNestApiException($statusCode, $code)';
}

class InkNestApiClient
    implements
        AuthService,
        AuthSessionInvalidationSource,
        FirstSignInCloudClient,
        SyncConflictCloudClient,
        SyncTombstoneCloudClient {
  InkNestApiClient({
    AppConfig? config,
    Dio? dio,
    Dio? refreshDio,
    AuthSessionStore? sessionStore,
    DateTime Function()? clock,
  }) : _config = config ?? AppConfig.fromEnvironment(),
       _dio = dio ?? Dio(),
       _refreshDio = refreshDio ?? Dio(),
       _sessionStore = sessionStore ?? SecureAuthSessionStore(),
       _clock = clock ?? DateTime.now,
       _ownsDio = dio == null,
       _ownsRefreshDio = refreshDio == null {
    _configure(_dio);
    _configure(_refreshDio);
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _authorize, onError: _refreshAfter401),
    );
  }

  static const _skipAuth = 'inknest.skipAuth';
  static const _retriedAfterRefresh = 'inknest.retriedAfterRefresh';
  static const _refreshLeeway = Duration(seconds: 30);

  final AppConfig _config;
  final Dio _dio;
  final Dio _refreshDio;
  final AuthSessionStore _sessionStore;
  final DateTime Function() _clock;
  final bool _ownsDio;
  final bool _ownsRefreshDio;

  Future<StoredAuthSession>? _refreshing;
  final StreamController<void> _sessionInvalidations =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get sessionInvalidations => _sessionInvalidations.stream;

  @override
  Future<InkNestAuthSession?> restoreSession() async {
    return (await _sessionStore.read())?.session;
  }

  @override
  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
    required String privacyPolicyVersion,
    required String termsVersion,
  }) async {
    final session = InkNestAuthSession.fromJson(
      await _postObject(
        'auth/register',
        data: {
          'email': email,
          'password': password,
          'deviceName': deviceName,
          'platform': platform,
          'clientInstanceId': clientInstanceId,
          'privacyPolicyVersion': privacyPolicyVersion,
          'termsVersion': termsVersion,
        },
        expectedStatus: 201,
        skipAuth: true,
      ),
    );
    await _storeSession(session);
    return session;
  }

  @override
  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    required String clientInstanceId,
  }) async {
    final session = InkNestAuthSession.fromJson(
      await _postObject(
        'auth/login',
        data: {
          'email': email,
          'password': password,
          'deviceName': deviceName,
          'platform': platform,
          'clientInstanceId': clientInstanceId,
        },
        expectedStatus: 200,
        skipAuth: true,
      ),
    );
    await _storeSession(session);
    return session;
  }

  Future<InkNestAuthSession> refresh() async {
    return (await _refreshStoredSession(force: true)).session;
  }

  @override
  Future<void> logout() async {
    final stored = await _sessionStore.read();
    if (stored == null) {
      return;
    }
    try {
      await _postNoContent(
        'auth/logout',
        data: {'refreshToken': stored.session.refreshToken},
        skipAuth: true,
      );
    } finally {
      await _sessionStore.clear();
    }
  }

  @override
  Future<InkNestCloudUser> acceptAgreements({
    required String privacyPolicyVersion,
    required String termsVersion,
  }) async {
    final user = InkNestCloudUser.fromJson(
      await _putObject(
        'me/agreements',
        data: {
          'privacyPolicyVersion': privacyPolicyVersion,
          'termsVersion': termsVersion,
        },
        expectedStatus: 200,
      ),
    );
    final stored = await _sessionStore.read();
    if (stored == null) {
      throw StateError('The account session is unavailable.');
    }
    await _storeSession(stored.session.copyWith(user: user));
    return user;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _putNoContent(
    'me/password',
    data: {'currentPassword': currentPassword, 'newPassword': newPassword},
  );

  @override
  Future<AccountDeletionResult> deleteAccount({
    required String password,
  }) async {
    final response = await _deleteObject(
      'me',
      data: {'password': password, 'confirmation': 'DELETE'},
      expectedStatus: 202,
    );
    final status = response['status'];
    final cloudDeletionComplete = response['cloudDeletionComplete'];
    final localDataRetained = response['localDataRetained'];
    if (status is! String ||
        cloudDeletionComplete is! bool ||
        localDataRetained is! bool) {
      throw const FormatException('Invalid account deletion response.');
    }
    await _sessionStore.clear();
    return AccountDeletionResult(
      status: status,
      cloudDeletionComplete: cloudDeletionComplete,
      localDataRetained: localDataRetained,
    );
  }

  @override
  Future<CloudSyncBootstrap> bootstrap() async {
    return CloudSyncBootstrap.fromJson(
      await _getObject('sync/bootstrap', expectedStatus: 200),
    );
  }

  @override
  Future<CloudSyncChangePage> listChanges({
    String? cursor,
    int limit = 100,
  }) async {
    if (cursor != null && (cursor.isEmpty || cursor.trim() != cursor)) {
      throw ArgumentError.value(cursor, 'cursor', 'Cursor must not be empty.');
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be from 1 to 500.');
    }
    return CloudSyncChangePage.fromJson(
      await _getObject(
        'sync/changes',
        expectedStatus: 200,
        queryParameters: {'cursor': ?cursor, 'limit': limit},
      ),
    );
  }

  @override
  Future<SyncMergeCommitResult> commitInitialMerge({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    return SyncMergeCommitResult.fromJson(
      await _postObject(
        'sync/merge/commit',
        data: {
          'deviceId': deviceId,
          'idempotencyKey': idempotencyKey,
          'baseCursor': baseCursor,
          'operations': operations,
        },
        expectedStatus: 200,
        skipAuth: false,
      ),
    );
  }

  @override
  Future<SyncContentCommitResult> commitSharedContent({
    required String deviceId,
    required String idempotencyKey,
    required String baseCursor,
    required List<Map<String, Object?>> operations,
  }) async {
    return SyncContentCommitResult.fromJson(
      await _postObject(
        'sync/commit',
        data: {
          'deviceId': deviceId,
          'idempotencyKey': idempotencyKey,
          'baseCursor': baseCursor,
          'operations': operations,
        },
        expectedStatus: 200,
        skipAuth: false,
      ),
    );
  }

  @override
  Future<CloudSyncConflict> resolveSyncConflict({
    required String conflictId,
    required SyncConflictResolution resolution,
  }) async {
    if (conflictId.isEmpty || conflictId.trim() != conflictId) {
      throw ArgumentError.value(
        conflictId,
        'conflictId',
        'Conflict ID must not be empty.',
      );
    }
    return CloudSyncConflict.fromJson(
      await _postObject(
        'sync/conflicts/${Uri.encodeComponent(conflictId)}/resolve',
        data: {'resolution': resolution.apiValue},
        expectedStatus: 200,
        skipAuth: false,
      ),
    );
  }

  @override
  Future<CloudSyncTombstone> restoreSyncTombstone(String tombstoneId) async {
    if (tombstoneId.isEmpty || tombstoneId.trim() != tombstoneId) {
      throw ArgumentError.value(
        tombstoneId,
        'tombstoneId',
        'Tombstone ID must not be empty.',
      );
    }
    return CloudSyncTombstone.fromJson(
      await _postObject(
        'sync/tombstones/${Uri.encodeComponent(tombstoneId)}/restore',
        data: const {},
        expectedStatus: 200,
        skipAuth: false,
      ),
    );
  }

  @override
  Future<CloudAssetUploadSession> createAssetUploadSession(
    LocalSyncAsset asset,
  ) async {
    return CloudAssetUploadSession.fromJson(
      await _postObject(
        'assets/upload-sessions',
        data: asset.toCreateJson(),
        expectedStatus: 201,
        skipAuth: false,
      ),
    );
  }

  @override
  Future<void> uploadAssetFile(
    CloudAssetUploadSession session,
    LocalSyncAsset asset,
  ) async {
    try {
      final response = await _refreshDio.put<Object?>(
        session.uploadUrl.toString(),
        data: asset.file.openRead(),
        options: Options(
          headers: {
            ...session.requiredHeaders,
            Headers.contentLengthHeader: asset.byteSize,
          },
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw _exceptionFromResponse(response);
      }
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  @override
  Future<void> completeAssetUpload(String uploadId) async {
    await _postObject(
      'assets/upload-sessions/${Uri.encodeComponent(uploadId)}/complete',
      data: const {},
      expectedStatus: 200,
      skipAuth: false,
    );
  }

  @override
  Future<CloudAssetDownload> createAssetDownload(String assetId) async {
    if (assetId.isEmpty || assetId.contains('/')) {
      throw ArgumentError.value(assetId, 'assetId', 'Invalid asset ID.');
    }
    return CloudAssetDownload.fromJson(
      await _getObject(
        'assets/${Uri.encodeComponent(assetId)}/download-url',
        expectedStatus: 200,
      ),
    );
  }

  @override
  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  ) async {
    await destination.parent.create(recursive: true);
    try {
      await _refreshDio.download(
        download.downloadUrl.toString(),
        destination.path,
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<void> clearLocalSession() => _sessionStore.clear();

  void close() {
    if (_ownsDio) {
      _dio.close(force: true);
    }
    if (_ownsRefreshDio) {
      _refreshDio.close(force: true);
    }
    unawaited(_sessionInvalidations.close());
  }

  void _configure(Dio dio) {
    dio.options
      ..baseUrl = _config.apiBaseUri.resolve('api/v1/').toString()
      ..connectTimeout = const Duration(seconds: 15)
      ..sendTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 30)
      ..responseType = ResponseType.json
      ..headers.addAll({'Accept': 'application/json'});
  }

  Future<void> _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuth] == true) {
      handler.next(options);
      return;
    }
    try {
      final stored = await _sessionForRequest();
      options.headers['Authorization'] = 'Bearer ${stored.session.accessToken}';
      handler.next(options);
    } on Object catch (error) {
      handler.reject(DioException(requestOptions: options, error: error), true);
    }
  }

  Future<void> _refreshAfter401(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        options.extra[_skipAuth] == true ||
        options.extra[_retriedAfterRefresh] == true) {
      handler.next(error);
      return;
    }
    try {
      final current = await _sessionStore.read();
      final sentAuthorization = options.headers['Authorization'];
      final stored =
          current != null &&
              sentAuthorization != 'Bearer ${current.session.accessToken}'
          ? current
          : await _refreshStoredSession(force: true);
      final response = await _dio.fetch<Object?>(
        options.copyWith(
          headers: {
            ...options.headers,
            'Authorization': 'Bearer ${stored.session.accessToken}',
          },
          extra: {...options.extra, _retriedAfterRefresh: true},
        ),
      );
      handler.resolve(response);
    } on Object catch (refreshError) {
      handler.reject(
        DioException(requestOptions: options, error: refreshError),
      );
    }
  }

  Future<StoredAuthSession> _sessionForRequest() async {
    final stored = await _sessionStore.read();
    if (stored == null) {
      throw const InkNestApiException(
        statusCode: 401,
        code: 'session_required',
        message: 'Sign in is required.',
        details: {},
      );
    }
    final refreshAt = stored.expiresAt.subtract(_refreshLeeway);
    if (!_clock().toUtc().isBefore(refreshAt)) {
      return _refreshStoredSession(force: true);
    }
    return stored;
  }

  Future<StoredAuthSession> _refreshStoredSession({required bool force}) async {
    final active = _refreshing;
    if (active != null) {
      return active;
    }
    final pending = _performRefresh(force: force);
    _refreshing = pending;
    try {
      return await pending;
    } finally {
      if (identical(_refreshing, pending)) {
        _refreshing = null;
      }
    }
  }

  Future<StoredAuthSession> _performRefresh({required bool force}) async {
    final stored = await _sessionStore.read();
    if (stored == null) {
      throw const InkNestApiException(
        statusCode: 401,
        code: 'session_required',
        message: 'Sign in is required.',
        details: {},
      );
    }
    if (!force && _clock().toUtc().isBefore(stored.expiresAt)) {
      return stored;
    }
    try {
      final response = await _refreshDio.post<Object?>(
        'auth/refresh',
        data: {'refreshToken': stored.session.refreshToken},
      );
      final session = InkNestAuthSession.fromJson(
        _decodeObject(response, expectedStatus: 200),
      );
      return _storeSession(session);
    } on DioException catch (error) {
      final exception = _exceptionFromDio(error);
      if (exception.statusCode == 401 || exception.statusCode == 403) {
        await _sessionStore.clear();
        _sessionInvalidations.add(null);
      }
      throw exception;
    }
  }

  Future<StoredAuthSession> _storeSession(InkNestAuthSession session) async {
    final stored = StoredAuthSession.fromSession(
      session,
      issuedAt: _clock().toUtc(),
    );
    await _sessionStore.write(stored);
    return stored;
  }

  Future<Map<String, Object?>> _getObject(
    String path, {
    required int expectedStatus,
    Map<String, Object?>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return _decodeObject(response, expectedStatus: expectedStatus);
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<Map<String, Object?>> _postObject(
    String path, {
    required Map<String, Object?> data,
    required int expectedStatus,
    required bool skipAuth,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: data,
        options: Options(extra: {_skipAuth: skipAuth}),
      );
      return _decodeObject(response, expectedStatus: expectedStatus);
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<Map<String, Object?>> _putObject(
    String path, {
    required Map<String, Object?> data,
    required int expectedStatus,
  }) async {
    try {
      final response = await _dio.put<Object?>(path, data: data);
      return _decodeObject(response, expectedStatus: expectedStatus);
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<Map<String, Object?>> _deleteObject(
    String path, {
    required Map<String, Object?> data,
    required int expectedStatus,
  }) async {
    try {
      final response = await _dio.delete<Object?>(path, data: data);
      return _decodeObject(response, expectedStatus: expectedStatus);
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<void> _putNoContent(
    String path, {
    required Map<String, Object?> data,
  }) async {
    try {
      final response = await _dio.put<Object?>(path, data: data);
      if (response.statusCode != 204) {
        throw _exceptionFromResponse(response);
      }
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Future<void> _postNoContent(
    String path, {
    required Map<String, Object?> data,
    required bool skipAuth,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: data,
        options: Options(extra: {_skipAuth: skipAuth}),
      );
      if (response.statusCode != 204) {
        throw _exceptionFromResponse(response);
      }
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  Map<String, Object?> _decodeObject(
    Response<Object?> response, {
    required int expectedStatus,
  }) {
    if (response.statusCode != expectedStatus) {
      throw _exceptionFromResponse(response);
    }
    final data = response.data;
    if (data is! Map<Object?, Object?> ||
        data.keys.any((key) => key is! String)) {
      throw const FormatException('The API response must be a JSON object.');
    }
    return data.cast<String, Object?>();
  }

  InkNestApiException _exceptionFromDio(DioException error) {
    final cause = error.error;
    if (cause is InkNestApiException) {
      return cause;
    }
    final response = error.response;
    if (response != null) {
      return _exceptionFromResponse(response);
    }
    return const InkNestApiException(
      statusCode: 0,
      code: 'network_error',
      message: 'InkNest Cloud could not be reached.',
      details: {},
    );
  }

  InkNestApiException _exceptionFromResponse(Response<Object?> response) {
    try {
      final root = response.data;
      if (root is Map<Object?, Object?> &&
          root.keys.every((key) => key is String)) {
        final rawError = root['error'];
        if (rawError is Map<Object?, Object?> &&
            rawError.keys.every((key) => key is String)) {
          final error = InkNestApiError.fromJson(
            rawError.cast<String, Object?>(),
          );
          return InkNestApiException(
            statusCode: response.statusCode ?? 0,
            code: error.code,
            message: error.message,
            details: error.details,
          );
        }
      }
    } on Object {
      // Fall through to a body-independent error so secrets are never copied
      // into logs or exception strings.
    }
    return InkNestApiException(
      statusCode: response.statusCode ?? 0,
      code: 'http_error',
      message: 'The InkNest service returned an invalid error response.',
      details: const {},
    );
  }
}
