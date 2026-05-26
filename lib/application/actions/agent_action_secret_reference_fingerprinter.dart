import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

/// Builds redacted fingerprints for `${secret:name}` references (never includes secret values).
class AgentActionSecretReferenceFingerprinter {
  const AgentActionSecretReferenceFingerprinter(this._secretStore);

  final IAgentActionSecretStore _secretStore;

  static const String missingFingerprint = 'missing';

  /// Sorted map of secret name → `sha256:<hex>` or [missingFingerprint].
  Future<Map<String, String>> fingerprintsFor(AgentActionDefinition definition) async {
    final names = AgentActionSecretPlaceholderScanner.collectFromDefinition(definition).toList()..sort();
    if (names.isEmpty) {
      return const <String, String>{};
    }

    if (!_secretStore.isAvailable) {
      return Map<String, String>.fromEntries(
        names.map((String name) => MapEntry<String, String>(name, missingFingerprint)),
      );
    }

    final result = <String, String>{};
    for (final name in names) {
      final value = await _secretStore.readSecret(name);
      if (value == null || value.isEmpty) {
        result[name] = missingFingerprint;
        continue;
      }
      final digest = sha256.convert(utf8.encode(value));
      result[name] = 'sha256:$digest';
    }
    return result;
  }
}
