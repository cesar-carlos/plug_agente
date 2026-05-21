/// Hub URL helpers for E2E (pure Dart, mirrors [ensureAgentsNamespaceUrl]).
library;

final RegExp _trailingSlashes = RegExp(r'/+$');
const String _agentsNamespace = 'agents';
const String _consumersNamespace = 'consumers';

String normalizeServerUrl(String serverUrl) {
  final trimmed = serverUrl.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed.replaceFirst(_trailingSlashes, '');
}

String joinServerUrlAndPath(String serverUrl, String path) {
  final normalized = normalizeServerUrl(serverUrl);
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalized$normalizedPath';
}

String ensureAgentsNamespaceUrl(String serverUrl) {
  final normalized = normalizeServerUrl(serverUrl);
  if (normalized.isEmpty) {
    return normalized;
  }

  final parsedUri = Uri.tryParse(normalized);
  if (parsedUri == null || (!parsedUri.hasScheme && !normalized.startsWith('//'))) {
    final lower = normalized.toLowerCase();
    if (lower.endsWith('/$_agentsNamespace')) {
      return normalized;
    }
    if (lower.endsWith('/$_consumersNamespace')) {
      return normalized.substring(0, normalized.length - _consumersNamespace.length) + _agentsNamespace;
    }
    return joinServerUrlAndPath(normalized, '/$_agentsNamespace');
  }

  final segments = parsedUri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last.toLowerCase() == _agentsNamespace) {
    return normalized;
  }
  if (segments.isNotEmpty && segments.last.toLowerCase() == _consumersNamespace) {
    segments[segments.length - 1] = _agentsNamespace;
  } else {
    segments.add(_agentsNamespace);
  }
  return parsedUri.replace(pathSegments: segments).toString();
}

bool isPlaceholderServerUrl(String serverUrl) {
  final lower = normalizeServerUrl(serverUrl).toLowerCase();
  return lower.isEmpty || lower == 'https://api.example.com';
}
