import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';

class RpcMethodConcurrencyLimiter {
  RpcMethodConcurrencyLimiter({
    required Map<String, int> methodLimits,
    this.enabled = true,
  }) : _methodLimits = Map.unmodifiable(methodLimits);

  factory RpcMethodConcurrencyLimiter.defaults({bool enabled = true}) {
    return RpcMethodConcurrencyLimiter(
      methodLimits: _defaultLimits,
      enabled: enabled,
    );
  }

  factory RpcMethodConcurrencyLimiter.fromEnvironment() {
    final enabled = _parseBool(
      AppEnvironment.get('RPC_METHOD_CONCURRENCY_LIMITS_ENABLED'),
      defaultValue: true,
    );
    final overrides = _parseOverrides(
      AppEnvironment.get('RPC_METHOD_CONCURRENCY_LIMITS'),
    );
    return RpcMethodConcurrencyLimiter(
      methodLimits: <String, int>{
        ..._defaultLimits,
        ...overrides,
      },
      enabled: enabled,
    );
  }

  static const Map<String, int> _defaultLimits = <String, int>{
    'sql.bulkInsert': 10,
    'sql.executeBatch': 20,
    'sql.execute': 40,
    AgentActionRpcConstants.agentActionRunRpcMethodName: 20,
    AgentActionRpcConstants.agentActionValidateRunRpcMethodName: 40,
    'sql.cancel': 80,
    'agent.getProfile': 80,
    'agent.getHealth': 80,
    'client_token.getPolicy': 80,
    AgentActionRpcConstants.agentActionCancelRpcMethodName: 80,
    AgentActionRpcConstants.agentActionGetExecutionRpcMethodName: 80,
  };

  final Map<String, int> _methodLimits;
  final bool enabled;
  final Map<String, int> _activeByKey = <String, int>{};

  int limitFor(String method) => _methodLimits[method] ?? 80;

  RpcMethodConcurrencyAcquireResult tryAcquire({
    required String method,
    required String agentId,
    required String? clientToken,
  }) {
    if (!enabled) {
      return RpcMethodConcurrencyAcquireResult.acquired(
        RpcMethodConcurrencyLease.noop(),
      );
    }

    final limit = limitFor(method);
    if (limit <= 0) {
      return RpcMethodConcurrencyAcquireResult.denied(limit: limit);
    }

    final key = _keyFor(
      method: method,
      agentId: agentId,
      clientToken: clientToken,
    );
    final active = _activeByKey[key] ?? 0;
    if (active >= limit) {
      return RpcMethodConcurrencyAcquireResult.denied(limit: limit);
    }

    _activeByKey[key] = active + 1;
    return RpcMethodConcurrencyAcquireResult.acquired(
      RpcMethodConcurrencyLease._(() {
        final current = _activeByKey[key] ?? 0;
        if (current <= 1) {
          _activeByKey.remove(key);
        } else {
          _activeByKey[key] = current - 1;
        }
      }),
    );
  }

  static String _keyFor({
    required String method,
    required String agentId,
    required String? clientToken,
  }) {
    final token = clientToken?.trim();
    if (token != null && token.isNotEmpty) {
      final digest = sha256.convert(utf8.encode(token)).toString();
      return '$method|client:$digest';
    }
    return '$method|agent:${agentId.trim()}';
  }

  static bool _parseBool(String? raw, {required bool defaultValue}) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return defaultValue;
    }
    return switch (normalized) {
      '1' || 'true' || 'yes' || 'y' || 'on' => true,
      '0' || 'false' || 'no' || 'n' || 'off' => false,
      _ => defaultValue,
    };
  }

  static Map<String, int> _parseOverrides(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String, int>{};
    }
    final parsed = <String, int>{};
    for (final entry in raw.split(',')) {
      final parts = entry.split('=');
      if (parts.length != 2) {
        continue;
      }
      final method = parts[0].trim();
      final limit = int.tryParse(parts[1].trim());
      if (method.isEmpty || limit == null) {
        continue;
      }
      parsed[method] = limit;
    }
    return parsed;
  }
}

class RpcMethodConcurrencyAcquireResult {
  const RpcMethodConcurrencyAcquireResult._({
    required this.acquired,
    required this.limit,
    this.lease,
  });

  factory RpcMethodConcurrencyAcquireResult.acquired(
    RpcMethodConcurrencyLease lease,
  ) {
    return RpcMethodConcurrencyAcquireResult._(
      acquired: true,
      limit: null,
      lease: lease,
    );
  }

  factory RpcMethodConcurrencyAcquireResult.denied({required int limit}) {
    return RpcMethodConcurrencyAcquireResult._(
      acquired: false,
      limit: limit,
    );
  }

  final bool acquired;
  final int? limit;
  final RpcMethodConcurrencyLease? lease;
}

class RpcMethodConcurrencyLease {
  RpcMethodConcurrencyLease.noop() : _release = null;

  RpcMethodConcurrencyLease._(void Function() release) : _release = release;

  final void Function()? _release;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _release?.call();
  }
}
