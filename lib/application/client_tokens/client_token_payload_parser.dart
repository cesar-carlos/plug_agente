import 'dart:convert';

enum ClientTokenPayloadParseError {
  invalidJson,
  notAnObject,
}

enum ClientTokenPayloadValidationError {
  databaseMustBeString,
  databaseCannotBeEmpty,
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

ClientTokenPayloadValidationError? validateClientTokenPayload(
  Map<String, dynamic> payload,
) {
  if (!payload.containsKey('database')) {
    return null;
  }

  final rawDatabase = payload['database'];
  if (rawDatabase is! String) {
    return ClientTokenPayloadValidationError.databaseMustBeString;
  }

  if (rawDatabase.trim().isEmpty) {
    return ClientTokenPayloadValidationError.databaseCannotBeEmpty;
  }

  return null;
}

String? normalizedPayloadDatabaseConstraint(Map<String, dynamic> payload) {
  final rawDatabase = payload['database'];
  if (rawDatabase is! String) {
    return null;
  }

  final normalized = rawDatabase.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
}
