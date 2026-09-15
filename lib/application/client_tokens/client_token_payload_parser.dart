import 'dart:convert';

enum ClientTokenPayloadParseError {
  invalidJson,
  notAnObject,
}

enum ClientTokenPayloadValidationError {
  databaseMustBeString,
  databaseCannotBeEmpty,
  runtimeRestrictionsInvalid,
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
  if (payload.containsKey('database')) {
    final rawDatabase = payload['database'];
    if (rawDatabase is! String) {
      return ClientTokenPayloadValidationError.databaseMustBeString;
    }

    if (rawDatabase.trim().isEmpty) {
      return ClientTokenPayloadValidationError.databaseCannotBeEmpty;
    }
  }

  for (final key in const <String>['token_scope', 'agent_action_scopes']) {
    if (payload.containsKey(key) && !_isScopeValue(payload[key])) {
      return ClientTokenPayloadValidationError.runtimeRestrictionsInvalid;
    }
  }

  if (!payload.containsKey('agent_actions')) {
    return null;
  }
  final rawAgentActions = payload['agent_actions'];
  if (rawAgentActions is! Map<String, dynamic>) {
    return ClientTokenPayloadValidationError.runtimeRestrictionsInvalid;
  }
  if (rawAgentActions.containsKey('scopes') && !_isScopeValue(rawAgentActions['scopes'])) {
    return ClientTokenPayloadValidationError.runtimeRestrictionsInvalid;
  }
  if (rawAgentActions.containsKey('action_ids') && !_isStringList(rawAgentActions['action_ids'])) {
    return ClientTokenPayloadValidationError.runtimeRestrictionsInvalid;
  }

  return null;
}

bool _isScopeValue(Object? value) => value is String || _isStringList(value);

bool _isStringList(Object? value) => value is List && value.every((item) => item is String);

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
