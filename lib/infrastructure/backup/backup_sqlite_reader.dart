import 'package:sqlite3/sqlite3.dart';

class BackupHubRow {
  const BackupHubRow({
    required this.agentId,
    required this.serverUrl,
    this.authToken,
    this.refreshToken,
  });

  final String agentId;
  final String serverUrl;
  final String? authToken;
  final String? refreshToken;
}

class BackupSqliteReader {
  BackupSqliteReader._();

  static int? readUserVersion(String path) {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final rs = db.select('PRAGMA user_version');
      if (rs.isEmpty) {
        return 0;
      }
      final v = rs.first.values.first;
      if (v is int) {
        return v;
      }
      if (v is num) {
        return v.toInt();
      }
      return int.tryParse(v.toString());
    } on Object {
      return null;
    } finally {
      db?.dispose();
    }
  }

  static BackupHubRow? readHubRow(String path) {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final rs = db.select(
        'SELECT agent_id, server_url, auth_token, refresh_token FROM config_table ORDER BY updated_at DESC LIMIT 1',
      );
      if (rs.isEmpty) {
        return null;
      }
      final row = rs.first;
      return BackupHubRow(
        agentId: row['agent_id'] as String? ?? '',
        serverUrl: row['server_url'] as String? ?? '',
        authToken: row['auth_token'] as String?,
        refreshToken: row['refresh_token'] as String?,
      );
    } on Object {
      return null;
    } finally {
      db?.dispose();
    }
  }
}
