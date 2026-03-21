import 'package:uuid/uuid.dart';

/// SQL snippets for ODBC live E2E (DDL + DML) keyed by detected driver family.
///
/// DDL is applied via the database gateway `executeNonQuery` (no RPC SQL validator).
/// DML is exercised through `sql.execute` / `sql.executeBatch`.
///
/// This is **path coverage** (real RPC + ODBC), not Dart line coverage (LCOV).
enum OdbcE2eSqlDialect {
  sqlAnywhere,
  sqlServer,
  postgresql,
}

/// Prefix for per-run table names (each [OdbcE2eLiveSql] instance uses a unique name).
const odbcE2eLiveTableNamePrefix = 'plug_agente_e2e_live';

/// Generates a unique table name for isolated parallel-safe E2E runs.
String newOdbcE2eLiveTableName() {
  final suffix = const Uuid().v4().replaceAll('-', '_');
  return '${odbcE2eLiveTableNamePrefix}_$suffix';
}

/// Best-effort detection from the ODBC connection string (DRIVER= / keywords).
OdbcE2eSqlDialect detectOdbcE2eDialect(String dsn) {
  final driverMatch = RegExp(
    r'DRIVER\s*=\s*\{([^}]+)\}',
    caseSensitive: false,
  ).firstMatch(dsn);
  final driver = driverMatch?.group(1)?.toUpperCase() ?? '';
  if (driver.contains('POSTGRE')) {
    return OdbcE2eSqlDialect.postgresql;
  }
  if (driver.contains('ANYWHERE') ||
      driver.contains('SYBASE') ||
      driver.contains('SQLA')) {
    return OdbcE2eSqlDialect.sqlAnywhere;
  }
  if (driver.contains('SQL SERVER')) {
    return OdbcE2eSqlDialect.sqlServer;
  }

  final u = dsn.toUpperCase();
  if (u.contains('POSTGRES')) {
    return OdbcE2eSqlDialect.postgresql;
  }
  if (u.contains('SQL ANYWHERE') || u.contains('SYBASE')) {
    return OdbcE2eSqlDialect.sqlAnywhere;
  }
  if (u.contains('SQL SERVER')) {
    return OdbcE2eSqlDialect.sqlServer;
  }
  return OdbcE2eSqlDialect.sqlServer;
}

class OdbcE2eLiveSql {
  OdbcE2eLiveSql(this.dialect, {required this.tableName});

  /// Driver family used for literals and DDL.
  final OdbcE2eSqlDialect dialect;

  /// Isolated table for this test group (see [newOdbcE2eLiveTableName]).
  final String tableName;

  String get dropTableIfExists => 'DROP TABLE IF EXISTS $tableName';

  String get createTable => switch (dialect) {
    OdbcE2eSqlDialect.sqlAnywhere =>
      '''
CREATE TABLE $tableName (
  id INTEGER NOT NULL PRIMARY KEY,
  code VARCHAR(40) NOT NULL,
  amt DECIMAL(10,2) NOT NULL,
  birth_date DATE NOT NULL,
  ts_col TIMESTAMP NOT NULL,
  is_active BIT NOT NULL
)
''',
    OdbcE2eSqlDialect.sqlServer =>
      '''
CREATE TABLE $tableName (
  id INT NOT NULL PRIMARY KEY,
  code NVARCHAR(40) NOT NULL,
  amt DECIMAL(10,2) NOT NULL,
  birth_date DATE NOT NULL,
  ts_col DATETIME2(3) NOT NULL,
  is_active BIT NOT NULL
)
''',
    OdbcE2eSqlDialect.postgresql =>
      '''
CREATE TABLE $tableName (
  id INTEGER NOT NULL PRIMARY KEY,
  code VARCHAR(40) NOT NULL,
  amt NUMERIC(10,2) NOT NULL,
  birth_date DATE NOT NULL,
  ts_col TIMESTAMP NOT NULL,
  is_active BOOLEAN NOT NULL
)
''',
  };

  String _boolLiteral(bool value) => switch (dialect) {
    OdbcE2eSqlDialect.postgresql => value ? 'TRUE' : 'FALSE',
    _ => value ? '1' : '0',
  };

  String insertRow({
    required int id,
    required String code,
    required double amt,
    required String birthDate,
    required String ts,
    required bool isActive,
  }) {
    final active = _boolLiteral(isActive);
    return switch (dialect) {
      OdbcE2eSqlDialect.postgresql =>
        '''
INSERT INTO $tableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, '$code', $amt, DATE '$birthDate', TIMESTAMP '$ts', $active
)
''',
      OdbcE2eSqlDialect.sqlServer =>
        '''
INSERT INTO $tableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, N'$code', $amt, CAST('$birthDate' AS DATE), CAST('$ts' AS DATETIME2(3)), $active
)
''',
      OdbcE2eSqlDialect.sqlAnywhere =>
        '''
INSERT INTO $tableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, '$code', $amt, '$birthDate', '$ts', $active
)
''',
    };
  }

  String get multiResultProbe =>
      '''
SELECT id, code, amt FROM $tableName WHERE id = 1;
SELECT COUNT(*) AS row_count FROM $tableName;
''';

  String updateAmtById(int id, double delta) =>
      'UPDATE $tableName SET amt = amt + $delta WHERE id = $id';

  /// Absolute assignment (for execution_order probes).
  String setAmtById(int id, double value) =>
      'UPDATE $tableName SET amt = $value WHERE id = $id';

  /// Multiplicative update (for execution_order probes).
  String multiplyAmtById(int id, double factor) =>
      'UPDATE $tableName SET amt = amt * $factor WHERE id = $id';

  String updateCodeById(int id, String code) =>
      "UPDATE $tableName SET code = '${code.replaceAll("'", "''")}' WHERE id = $id";

  String deleteById(int id) => 'DELETE FROM $tableName WHERE id = $id';

  String get countAll => 'SELECT COUNT(*) AS row_count FROM $tableName';

  /// Single-row probe for batch SELECT coverage (same shape for SA / SQL Server / PostgreSQL).
  String selectIdCodeAmtById(int id) =>
      'SELECT id, code, amt FROM $tableName WHERE id = $id';

  /// Stable ordering for pagination / streaming probes.
  String get selectIdCodeOrderById =>
      'SELECT id, code FROM $tableName ORDER BY id';

  /// ODBC named placeholder for [key] (`@key` on SQL Server, `:key` elsewhere).
  String namedPlaceholder(String key) => switch (dialect) {
    OdbcE2eSqlDialect.sqlServer => '@$key',
    _ => ':$key',
  };

  /// `SELECT code ... WHERE id = <named>` — use `params: { idKey: <int> }`.
  String selectCodeWhereIdNamed(String idKey) {
    final p = namedPlaceholder(idKey);
    return 'SELECT code FROM $tableName WHERE id = $p';
  }

  /// `UPDATE ... SET code = <codeKey> WHERE id = <idKey>` with bound params.
  String updateCodeWhereIdNamed(String codeKey, String idKey) {
    final c = namedPlaceholder(codeKey);
    final i = namedPlaceholder(idKey);
    return 'UPDATE $tableName SET code = $c WHERE id = $i';
  }
}
