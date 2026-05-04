// Shared heuristics for whether a Socket.IO `connect_error` indicates hub
// authentication/session rejection (vs pure transport/network issues).

const List<String> _hubConnectAuthMessageMarkers = <String>[
  'authentication',
  'invalid token',
  'invalid_token',
  '401',
  '403',
  'unauthorized',
  'forbidden',
  'jwt',
  'token_expired',
  'token expired',
  'token_revoked',
  'session expired',
  'refresh_token',
  'credential',
];

/// Returns false for obvious TCP transport strings to avoid treating them as auth.
bool isHubConnectAuthRelatedMessage(String errorMessage) {
  final m = errorMessage.trim().toLowerCase();
  if (m.isEmpty) {
    return false;
  }
  if (m.contains('connection refused') || m.contains('connection reset')) {
    return false;
  }
  for (final marker in _hubConnectAuthMessageMarkers) {
    if (m.contains(marker)) {
      return true;
    }
  }
  return false;
}

/// Structured hub payloads: `code` / `reason` from JSON maps.
bool isHubConnectAuthRelatedStructured({String? code, String? reason}) {
  bool field(String? s) {
    if (s == null || s.trim().isEmpty) {
      return false;
    }
    final lc = s.toLowerCase();
    if (lc.contains('auth')) {
      return true;
    }
    if (lc == 'unauthorized' || lc == '401' || lc == '403') {
      return true;
    }
    if (lc.contains('token') || lc.contains('jwt')) {
      return true;
    }
    if (lc.contains('forbidden')) {
      return true;
    }
    return false;
  }

  return field(code) || field(reason);
}
