class AppConfig {
  AppConfig._(this.apiBaseUri);

  static const String defaultApiBaseUrl = 'http://127.0.0.1:8000';
  static const String environmentApiBaseUrl = String.fromEnvironment(
    'INKNEST_API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );

  final Uri apiBaseUri;

  factory AppConfig.fromEnvironment({String? overrideApiBaseUrl}) {
    return AppConfig._(
      _parseApiBaseUri(overrideApiBaseUrl ?? environmentApiBaseUrl),
    );
  }

  static Uri _parseApiBaseUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw FormatException('Invalid InkNest API base URL: $value');
    }
    return uri.replace(path: '/');
  }
}
