import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:sqlite3/sqlite3.dart';

class ElevatedExecutionContext {
  const ElevatedExecutionContext({
    required this.executionId,
    required this.actionId,
    required this.actionType,
    required this.definitionState,
    required this.config,
    required this.policies,
  });

  final String executionId;
  final String actionId;
  final String actionType;
  final String definitionState;
  final Map<String, dynamic> config;
  final Map<String, dynamic> policies;
}

class ElevatedSqliteStore {
  ElevatedSqliteStore({required this.appDirectoryPath});

  final String appDirectoryPath;

  ElevatedExecutionContext? loadExecutionContext(String executionId) {
    final dbPath = ElevatedContract.databasePath(appDirectoryPath);
    if (!p.isAbsolute(dbPath)) {
      return null;
    }
    final database = sqlite3.open(dbPath);
    try {
      final statement = database.prepare('''
SELECT
  e.id AS execution_id,
  e.action_id AS action_id,
  e.action_type AS action_type,
  d.state AS definition_state,
  d.config_json AS config_json,
  d.policies_json AS policies_json
FROM agent_action_execution_table e
INNER JOIN agent_action_definition_table d ON d.id = e.action_id
WHERE e.id = ?
LIMIT 1
''');
      try {
        final rows = statement.select(<Object?>[executionId.trim()]);
        if (rows.isEmpty) {
          return null;
        }
        final row = rows.first;
        return ElevatedExecutionContext(
          executionId: row['execution_id'] as String,
          actionId: row['action_id'] as String,
          actionType: row['action_type'] as String,
          definitionState: row['definition_state'] as String,
          config: _decodeObject(row['config_json'] as String),
          policies: _decodeObject(row['policies_json'] as String),
        );
      } finally {
        statement.dispose();
      }
    } finally {
      database.dispose();
    }
  }

  Map<String, dynamic> _decodeObject(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const <String, dynamic>{};
  }
}
