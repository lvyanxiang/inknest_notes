class InkNestApiConfig {
  InkNestApiConfig._(this.baseUri);

  static const String defaultBaseUrl = 'http://127.0.0.1:8000';
  static const String environmentBaseUrl = String.fromEnvironment(
    'INKNEST_API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );

  final Uri baseUri;

  factory InkNestApiConfig.fromEnvironment({String? overrideBaseUrl}) {
    return InkNestApiConfig._(
      _parseBaseUri(overrideBaseUrl ?? environmentBaseUrl),
    );
  }

  static Uri _parseBaseUri(String value) {
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
