import 'dart:developer' as developer;

import 'package:plug_agente/core/config/app_environment.dart';

/// Shared environment parsing for connection-related constant modules.
abstract final class ConnectionConstantsEnv {
  ConnectionConstantsEnv._();

  static String? optional(String key) => AppEnvironment.get(key);

  static final Set<String> _loggedInvalidPositiveIntEnvKeys = <String>{};

  static int? positiveInt(String key) {
    final raw = optional(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if ((parsed == null || parsed <= 0) && _loggedInvalidPositiveIntEnvKeys.add(key)) {
      developer.log(
        'Ignoring invalid positive integer env override: $key',
        name: 'connection_constants',
        level: 900,
        error: {
          'key': key,
          'value': raw,
        },
      );
    }
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
