import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

class AgentActionPreparedExecutionCache {
  AgentActionPreparedExecutionCache({
    Duration? ttl,
    DateTime Function()? now,
  }) : _ttl = ttl ?? AgentActionGateConstants.remotePreparedExecutionCacheTtl,
       _now = now ?? DateTime.now;

  final Duration _ttl;
  final DateTime Function() _now;
  final Map<String, _AgentActionPreparedExecutionCacheEntry> _entries =
      <String, _AgentActionPreparedExecutionCacheEntry>{};

  void store({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionPreparedExecution prepared,
  }) {
    if (request.source != AgentActionRequestSource.remoteHub) {
      return;
    }

    _purgeExpired();
    final key = _cacheKeyFor(definition: definition, request: request);
    if (key == null) {
      return;
    }

    _entries[key] = _AgentActionPreparedExecutionCacheEntry(
      prepared: prepared,
      definitionSnapshotHash: definition.definitionSnapshotHash,
      requestFingerprint: requestFingerprint(
        definition: definition,
        request: request,
      ),
      storedAt: _now(),
    );
  }

  AgentActionPreparedExecution? consumeIfValid({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    if (request.source != AgentActionRequestSource.remoteHub) {
      return null;
    }

    _purgeExpired();
    final key = _cacheKeyFor(definition: definition, request: request);
    if (key == null) {
      return null;
    }

    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }

    if (entry.isExpired(_now(), _ttl)) {
      return null;
    }
    if (entry.definitionSnapshotHash != definition.definitionSnapshotHash) {
      return null;
    }
    if (entry.requestFingerprint !=
        requestFingerprint(
          definition: definition,
          request: request,
        )) {
      return null;
    }

    return entry.prepared;
  }

  void invalidateFor({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final key = _cacheKeyFor(definition: definition, request: request);
    if (key == null) {
      return;
    }
    _entries.remove(key);
  }

  String? _cacheKeyFor({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final actionId = request.actionId.trim();
    if (actionId.isEmpty) {
      return null;
    }

    final idempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    if (idempotencyKey != null) {
      return '$actionId:$idempotencyKey';
    }

    return '$actionId:${requestFingerprint(definition: definition, request: request)}';
  }

  void _purgeExpired() {
    final now = _now();
    _entries.removeWhere(
      (_, entry) => entry.isExpired(now, _ttl),
    );
  }
}

String requestFingerprint({
  required AgentActionDefinition definition,
  required AgentActionExecutionRequest request,
}) {
  return buildIdempotencyFingerprintForEnvelope(
    <String, dynamic>{
      'action_id': request.actionId.trim(),
      'source': request.source.name,
      'definition_snapshot_hash': definition.definitionSnapshotHash,
      'context_path': _canonicalOptionalRequestString(request.contextPath),
      'runtime_parameters': canonicalizeJsonValueForIdempotency(request.runtimeParameters),
      'dangerous_command_confirmed': request.dangerousCommandConfirmed,
    },
  );
}

String? _canonicalOptionalRequestString(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class _AgentActionPreparedExecutionCacheEntry {
  const _AgentActionPreparedExecutionCacheEntry({
    required this.prepared,
    required this.definitionSnapshotHash,
    required this.requestFingerprint,
    required this.storedAt,
  });

  final AgentActionPreparedExecution prepared;
  final String? definitionSnapshotHash;
  final String requestFingerprint;
  final DateTime storedAt;

  bool isExpired(DateTime now, Duration ttl) => now.difference(storedAt) > ttl;
}
