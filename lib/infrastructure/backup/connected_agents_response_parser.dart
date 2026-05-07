import 'dart:convert';

/// Parses `GET /api/v1/agents` style responses: JSON array or `{ "agents": [...] }`.
///
/// Project overview describes the list as connected agents; if an entry matches
/// the given agent ID, the agent is treated as connected unless the payload explicitly sets
/// `connected`, `isOnline`, or `online` to `false`.
class ConnectedAgentsResponseParser {
  ConnectedAgentsResponseParser._();

  static bool isAgentIdListedAsConnected(String body, String agentId) {
    final trimmedId = agentId.trim();
    if (trimmedId.isEmpty) {
      return false;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return false;
    }

    final list = _coerceToList(decoded);
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final id = raw['id'] ?? raw['agentId'] ?? raw['agent_id'];
      if (id?.toString().trim() != trimmedId) {
        continue;
      }
      final explicit = raw['connected'] ?? raw['isOnline'] ?? raw['online'];
      if (explicit is bool) {
        return explicit;
      }
      return true;
    }
    return false;
  }

  static List<dynamic> _coerceToList(dynamic decoded) {
    if (decoded is List<dynamic>) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final agents = decoded['agents'];
      if (agents is List<dynamic>) {
        return agents;
      }
      final data = decoded['data'];
      if (data is List<dynamic>) {
        return data;
      }
    }
    return <dynamic>[];
  }
}
