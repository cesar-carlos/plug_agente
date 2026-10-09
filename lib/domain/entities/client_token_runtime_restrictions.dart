// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: This value object stores immutable collections and compares policy
// restrictions by their authorization semantics.

/// Runtime constraints encoded in a client-token payload.
///
/// They are deliberately separate from the SQL policy flags: a token can have
/// global SQL permissions and still be restricted to one database or to a
/// subset of remote agent actions.
class ClientTokenRuntimeRestrictions {
  const ClientTokenRuntimeRestrictions({
    required this.declaresAgentActionMetadata,
    required this.agentActionScopes,
    required this.hasActionIdAllowlist,
    required this.actionIds,
    this.database,
  });

  factory ClientTokenRuntimeRestrictions.fromPayload(Map<String, dynamic> payload) {
    if (!isValidPayload(payload)) throw const FormatException('Invalid token runtime restrictions');
    final databaseValue = payload['database'];
    final database = databaseValue is String && databaseValue.trim().isNotEmpty ? databaseValue.trim() : null;
    final nested = payload['agent_actions'];
    final agentActions = nested is Map ? Map<String, dynamic>.from(nested) : null;
    final declaresMetadata =
        payload.containsKey('token_scope') ||
        payload.containsKey('agent_action_scopes') ||
        (agentActions?.containsKey('scopes') ?? false) ||
        (agentActions?.containsKey('action_ids') ?? false);
    final scopes = <String>{};
    _addScopes(scopes, payload['token_scope']);
    _addScopes(scopes, payload['agent_action_scopes']);
    _addScopes(scopes, agentActions?['scopes']);
    final actionIds = _parseStringSet(agentActions?['action_ids']);
    return ClientTokenRuntimeRestrictions(
      database: database,
      declaresAgentActionMetadata: declaresMetadata,
      agentActionScopes: Set.unmodifiable(scopes.map((scope) => scope.toLowerCase())),
      hasActionIdAllowlist: agentActions?.containsKey('action_ids') ?? false,
      actionIds: Set.unmodifiable(actionIds),
    );
  }

  static bool isValidPayload(Map<String, dynamic> payload) {
    if (payload.containsKey('database')) {
      final value = payload['database'];
      if (value is! String || value.trim().isEmpty) return false;
    }
    for (final key in ['token_scope', 'agent_action_scopes']) {
      if (payload.containsKey(key) && !_isScopeValue(payload[key])) return false;
    }
    if (!payload.containsKey('agent_actions')) return true;
    final actions = payload['agent_actions'];
    if (actions is! Map<String, dynamic>) return false;
    if (actions.containsKey('scopes') && !_isScopeValue(actions['scopes'])) return false;
    return !actions.containsKey('action_ids') || _isStringList(actions['action_ids']);
  }

  static bool _isScopeValue(Object? value) => value is String || _isStringList(value);
  static bool _isStringList(Object? value) => value is List && value.every((item) => item is String);

  final String? database;
  final bool declaresAgentActionMetadata;
  final Set<String> agentActionScopes;
  final bool hasActionIdAllowlist;
  final Set<String> actionIds;

  bool get hasRestrictions => database != null || declaresAgentActionMetadata;

  /// Database matching is case-insensitive, unlike action IDs.
  String? get normalizedDatabase => database?.toLowerCase();

  @override
  bool operator ==(Object other) {
    return other is ClientTokenRuntimeRestrictions &&
        other.normalizedDatabase == normalizedDatabase &&
        other.declaresAgentActionMetadata == declaresAgentActionMetadata &&
        other.hasActionIdAllowlist == hasActionIdAllowlist &&
        _setsEqual(other.agentActionScopes, agentActionScopes) &&
        _setsEqual(other.actionIds, actionIds);
  }

  @override
  int get hashCode => Object.hash(
    normalizedDatabase,
    declaresAgentActionMetadata,
    hasActionIdAllowlist,
    Object.hashAll(agentActionScopes.toList()..sort()),
    Object.hashAll(actionIds.toList()..sort()),
  );

  static void _addScopes(Set<String> target, Object? raw) {
    if (raw is String) {
      for (final part in raw.split(RegExp(r'[\s,]+'))) {
        final value = part.trim();
        if (value.isNotEmpty) target.add(value);
      }
    } else if (raw is Iterable) {
      for (final value in raw.whereType<String>()) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) target.add(trimmed);
      }
    }
  }

  static Set<String> _parseStringSet(Object? raw) => raw is Iterable
      ? raw.whereType<String>().map((value) => value.trim()).where((value) => value.isNotEmpty).toSet()
      : <String>{};

  static bool _setsEqual(Set<String> left, Set<String> right) => left.length == right.length && left.containsAll(right);
}
