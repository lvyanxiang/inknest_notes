import 'dart:convert';

import 'package:http/http.dart' as http;
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

class InkNestApiClient {
  InkNestApiClient({InkNestApiConfig? config, http.Client? httpClient})
    : _config = config ?? InkNestApiConfig.fromEnvironment(),
      _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  final InkNestApiConfig _config;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<InkNestAuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _httpClient.post(
      _endpoint('auth/register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceName': deviceName,
        'platform': platform,
      }),
    );
    return InkNestAuthSession.fromJson(
      _decodeSuccessObject(response, expectedStatus: 201),
    );
  }

  Future<InkNestAuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _httpClient.post(
      _endpoint('auth/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceName': deviceName,
        'platform': platform,
      }),
    );
    return InkNestAuthSession.fromJson(
      _decodeSuccessObject(response, expectedStatus: 200),
    );
  }

  Future<InkNestAuthSession> refresh(String refreshToken) async {
    final response = await _httpClient.post(
      _endpoint('auth/refresh'),
      headers: _jsonHeaders(),
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    return InkNestAuthSession.fromJson(
      _decodeSuccessObject(response, expectedStatus: 200),
    );
  }

  Future<void> logout(String refreshToken) async {
    final response = await _httpClient.post(
      _endpoint('auth/logout'),
      headers: _jsonHeaders(),
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode != 204) {
      _throwApiError(response);
    }
  }

  Future<CloudSyncBootstrap> bootstrap({required String accessToken}) async {
    final response = await _httpClient.get(
      _endpoint('sync/bootstrap'),
      headers: _jsonHeaders(accessToken: accessToken),
    );
    return CloudSyncBootstrap.fromJson(
      _decodeSuccessObject(response, expectedStatus: 200),
    );
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Uri _endpoint(String path) => _config.baseUri.resolve('api/v1/$path');

  Map<String, String> _jsonHeaders({String? accessToken}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, Object?> _decodeSuccessObject(
    http.Response response, {
    required int expectedStatus,
  }) {
    if (response.statusCode != expectedStatus) {
      _throwApiError(response);
    }
    final decoded = _decodeJson(response.bodyBytes);
    if (decoded is! Map<Object?, Object?> ||
        decoded.keys.any((key) => key is! String)) {
      throw const FormatException('The API response must be a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  Never _throwApiError(http.Response response) {
    try {
      final decoded = _decodeJson(response.bodyBytes);
      if (decoded is Map<Object?, Object?>) {
        final root = decoded.cast<String, Object?>();
        final rawError = root['error'];
        if (rawError is Map<Object?, Object?>) {
          final error = InkNestApiError.fromJson(
            rawError.cast<String, Object?>(),
          );
          throw InkNestApiException(
            statusCode: response.statusCode,
            code: error.code,
            message: error.message,
            details: error.details,
          );
        }
      }
    } on InkNestApiException {
      rethrow;
    } on Object {
      // Fall through to a body-independent error so tokens and signed URLs are
      // never copied into logs or exception messages.
    }
    throw InkNestApiException(
      statusCode: response.statusCode,
      code: 'http_error',
      message: 'The InkNest service returned an invalid error response.',
      details: const {},
    );
  }
}

Object? _decodeJson(List<int> bodyBytes) {
  try {
    return jsonDecode(utf8.decode(bodyBytes));
  } on Object catch (error) {
    throw FormatException('The API response is not valid UTF-8 JSON.', error);
  }
}
