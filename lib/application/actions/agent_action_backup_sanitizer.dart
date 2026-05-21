import 'dart:convert';

import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_portable_codec.dart';

/// Prepares portable JSON for backup/export without secret values and strips remote approval.
class AgentActionBackupSanitizer {
  AgentActionBackupSanitizer({
    required IAgentActionPortableCodec codec,
    AgentActionDefinitionSnapshotter? snapshotter,
    AgentActionRedactor? literalRedactor,
    DateTime Function()? now,
  }) : _codec = codec,
       _snapshotter = snapshotter ?? const AgentActionDefinitionSnapshotter(),
       _literalRedactor = literalRedactor ?? const AgentActionRedactor(),
       _now = now ?? DateTime.now;

  final IAgentActionPortableCodec _codec;
  final AgentActionDefinitionSnapshotter _snapshotter;
  final AgentActionRedactor _literalRedactor;
  final DateTime Function() _now;

  Map<String, Object?> buildExportBundle({
    required List<AgentActionDefinition> definitions,
    required List<AgentActionTrigger> triggers,
  }) {
    return <String, Object?>{
      'export_schema': AgentActionBackupConstants.exportSchemaV1,
      'exported_at_utc': _now().toUtc().toIso8601String(),
      'definitions': definitions.map(sanitizeDefinitionForExport).toList(growable: false),
      'triggers': triggers.map(sanitizeTriggerForExport).toList(growable: false),
      'secret_placeholders_referenced': _collectSecretPlaceholders(definitions).toList(growable: false)..sort(),
    };
  }

  Map<String, Object?> sanitizeDefinitionForExport(AgentActionDefinition definition) {
    final portable = _codec.definitionToPortableJson(definition);
    return <String, Object?>{
      'id': portable['id'],
      'name': portable['name'],
      'description': _sanitizeOptionalString(portable['description'] as String?),
      'type': portable['type'],
      'state': definition.state.name,
      'definitionVersion': portable['definitionVersion'],
      'config': _sanitizeJsonMap(_readObject(portable, 'config')),
      'policies': _sanitizePoliciesForExport(_readObject(portable, 'policies')),
      'definition_snapshot_hash': _snapshotter.snapshotHash(definition),
    };
  }

  Map<String, Object?> sanitizeTriggerForExport(AgentActionTrigger trigger) {
    final portable = _codec.triggerToPortableJson(trigger);
    return <String, Object?>{
      'id': portable['id'],
      'actionId': portable['actionId'],
      'type': portable['type'],
      'name': _sanitizeOptionalString(portable['name'] as String?),
      'isEnabled': false,
      'schedule': _sanitizeJsonMap(_readObject(portable, 'schedule')),
      'export_note': 'Triggers are exported paused; re-enable after validating paths and secrets on this machine.',
    };
  }

  AgentActionDefinition prepareDefinitionForImport(Map<String, Object?> json) {
    final sanitized = _sanitizeJsonMap(json)
      ..remove('definition_snapshot_hash')
      ..remove('export_note');
    final policies = _readObject(sanitized, 'policies');
    final remote = _readObject(policies, 'remote');
    policies['remote'] = <String, Object?>{
      'isEnabled': false,
      'allowAdHoc': remote['allowAdHoc'] as bool? ?? false,
      'requiresReapproval': true,
    };
    sanitized['policies'] = policies;
    sanitized['state'] = AgentActionState.needsValidation.name;

    final definition = _codec.definitionFromPortableJson(sanitized);
    return definition.copyWith(
      state: AgentActionState.needsValidation,
      policies: definition.policies.copyWith(
        remote: AgentActionRemotePolicy(
          allowAdHoc: definition.policies.remote.allowAdHoc,
          requiresReapproval: true,
        ),
      ),
    );
  }

  AgentActionTrigger prepareTriggerForImport(Map<String, Object?> json) {
    final sanitized = _sanitizeJsonMap(json)..remove('export_note');
    sanitized['isEnabled'] = false;
    return _codec.triggerFromPortableJson(sanitized).copyWith(isEnabled: false);
  }

  Set<String> secretPlaceholdersInBundle(Map<String, Object?> bundle) {
    final definitions = bundle['definitions'];
    if (definitions is! List) {
      return const {};
    }
    final names = <String>{};
    for (final Object? raw in definitions) {
      if (raw is! Map) {
        continue;
      }
      names.addAll(AgentActionSecretPlaceholderScanner.collectFromText(jsonEncode(raw)));
    }
    return names;
  }

  Map<String, Object?> _sanitizePoliciesForExport(Map<String, Object?> policies) {
    final sanitized = _sanitizeJsonMap(policies);
    final remote = Map<String, Object?>.from(_readObject(sanitized, 'remote'));
    remote
      ..remove('approvedBy')
      ..remove('approvedAt')
      ..remove('approvalReason')
      ..remove('riskFingerprint');
    remote['isEnabled'] = false;
    remote['requiresReapproval'] = true;
    sanitized['remote'] = remote;
    return sanitized;
  }

  Map<String, Object?> _sanitizeJsonMap(Map<String, Object?> source) {
    final out = <String, Object?>{};
    for (final entry in source.entries) {
      out[entry.key] = _sanitizeJsonValue(entry.value);
    }
    return out;
  }

  Object? _sanitizeJsonValue(Object? value) {
    if (value is String) {
      return _sanitizeExportString(value);
    }
    if (value is Map) {
      return _sanitizeJsonMap(Map<String, Object?>.from(value.cast<String, Object?>()));
    }
    if (value is List) {
      return value.map(_sanitizeJsonValue).toList(growable: false);
    }
    return value;
  }

  String? _sanitizeOptionalString(String? value) {
    if (value == null) {
      return null;
    }
    return _sanitizeExportString(value);
  }

  String _sanitizeExportString(String value) {
    if (value.isEmpty) {
      return value;
    }

    final buffer = StringBuffer();
    var segmentStart = 0;
    for (final Match match in AgentActionSecretPlaceholderScanner.placeholderPattern.allMatches(value)) {
      if (match.start > segmentStart) {
        buffer.write(_literalRedactor.redactText(value.substring(segmentStart, match.start)));
      }
      buffer.write(match.group(0));
      segmentStart = match.end;
    }
    if (segmentStart < value.length) {
      buffer.write(_literalRedactor.redactText(value.substring(segmentStart)));
    }
    return buffer.toString();
  }

  Set<String> _collectSecretPlaceholders(List<AgentActionDefinition> definitions) {
    final names = <String>{};
    for (final definition in definitions) {
      names.addAll(AgentActionSecretPlaceholderScanner.collectFromDefinition(definition));
    }
    return names;
  }

  Map<String, Object?> _readObject(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is Map) {
      return Map<String, Object?>.from(value.cast<String, Object?>());
    }
    return <String, Object?>{};
  }
}
