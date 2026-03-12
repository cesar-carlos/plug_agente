String normalizeServerUrl(String serverUrl) {
  final trimmedServerUrl = serverUrl.trim();
  if (trimmedServerUrl.isEmpty) {
    return trimmedServerUrl;
  }
  return trimmedServerUrl.replaceFirst(RegExp(r'/+$'), '');
}

String joinServerUrlAndPath(String serverUrl, String path) {
  final normalizedServerUrl = normalizeServerUrl(serverUrl);
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedServerUrl$normalizedPath';
}
