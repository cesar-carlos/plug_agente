final RegExp _trailingSlashes = RegExp(r'/+$');
const String _agentsNamespace = 'agents';
const String _consumersNamespace = 'consumers';

String normalizeServerUrl(String serverUrl) {
  final trimmedServerUrl = serverUrl.trim();
  if (trimmedServerUrl.isEmpty) {
    return trimmedServerUrl;
  }
  return trimmedServerUrl.replaceFirst(_trailingSlashes, '');
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
    final lowerUrl = normalizedServerUrl.toLowerCase();
    if (lowerUrl.endsWith('/$_agentsNamespace')) {
      return normalizedServerUrl;
    }
    if (lowerUrl.endsWith('/$_consumersNamespace')) {
      return normalizedServerUrl.substring(0, normalizedServerUrl.length - _consumersNamespace.length) +
          _agentsNamespace;
    }
    return joinServerUrlAndPath(normalizedServerUrl, '/$_agentsNamespace');
  }

  final pathSegments = parsedUri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (pathSegments.isNotEmpty && pathSegments.last.toLowerCase() == _agentsNamespace) {
    return normalizedServerUrl;
  }

  if (pathSegments.isNotEmpty && pathSegments.last.toLowerCase() == _consumersNamespace) {
    pathSegments[pathSegments.length - 1] = _agentsNamespace;
  } else {
    pathSegments.add(_agentsNamespace);
  }
  return parsedUri.replace(pathSegments: pathSegments).toString();
}
