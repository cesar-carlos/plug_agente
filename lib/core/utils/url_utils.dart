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

String ensureAgentsNamespaceUrl(String serverUrl) {
  final normalizedServerUrl = normalizeServerUrl(serverUrl);
  if (normalizedServerUrl.isEmpty) {
    return normalizedServerUrl;
  }

  final parsedUri = Uri.tryParse(normalizedServerUrl);
  if (parsedUri == null || (!parsedUri.hasScheme && !normalizedServerUrl.startsWith('//'))) {
    if (normalizedServerUrl.toLowerCase().endsWith('/agents')) {
      return normalizedServerUrl;
    }
    return joinServerUrlAndPath(normalizedServerUrl, '/agents');
  }

  final pathSegments = parsedUri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (pathSegments.isNotEmpty && pathSegments.last.toLowerCase() == 'agents') {
    return normalizedServerUrl;
  }

  pathSegments.add('agents');
  return parsedUri.replace(pathSegments: pathSegments).toString();
}
