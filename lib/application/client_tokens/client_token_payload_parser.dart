import 'dart:convert';

enum ClientTokenPayloadParseError {
  invalidJson,
  notAnObject,
}

({Map<String, dynamic>? payload, ClientTokenPayloadParseError? error}) parseClientTokenPayloadJson(
  String raw,
) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return (payload: const <String, dynamic>{}, error: null);
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      return (payload: decoded, error: null);
    }
    return (payload: null, error: ClientTokenPayloadParseError.notAnObject);
  } on FormatException {
    return (payload: null, error: ClientTokenPayloadParseError.invalidJson);
  }
}
