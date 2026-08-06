import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:inknest_notes/auth/auth_service.dart';
import 'package:inknest_notes/auth/auth_session_store.dart';
import 'package:inknest_notes/sync/inknest_api_config.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';

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

abstract interface class CloudAssetTransferClient {
  Future<CloudAssetDownload> createAssetDownload(String assetId);

  Future<void> downloadAssetToFile(
    CloudAssetDownload download,
    File destination,
  );
}

class InkNestApiClient
    implements
        AuthService,
        AuthSessionInvalidationSource,
        CloudAssetTransferClient {
  InkNestApiClient({
    InkNestApiConfig? config,
    Dio? dio,
    Dio? refreshDio,
    AuthSessionStore? sessionStore,
    DateTime Function()? clock,
  }) : _config = config ?? InkNestApiConfig.fromEnvironment(),
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

  final InkNestApiConfig _config;
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
  }) async {
    final session = InkNestAuthSession.fromJson(
      await _postObject(
        'auth/register',
        data: {
          'email': email,
          'password': password,
          'deviceName': deviceName,
          'platform': platform,
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
  }) async {
    final session = InkNestAuthSession.fromJson(
      await _postObject(
        'auth/login',
        data: {
          'email': email,
          'password': password,
          'deviceName': deviceName,
          'platform': platform,
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

  Future<CloudSyncBootstrap> bootstrap() async {
    return CloudSyncBootstrap.fromJson(
      await _getObject('sync/bootstrap', expectedStatus: 200),
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
      ..baseUrl = _config.baseUri.resolve('api/v1/').toString()
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
  }) async {
    try {
      final response = await _dio.get<Object?>(path);
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
