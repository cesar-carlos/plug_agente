/// SQL snippets for ODBC E2E coverage (DDL + DML) keyed by detected driver family.
///
/// DDL is applied via the database gateway `executeNonQuery` (no RPC SQL validator).
/// DML is exercised through `sql.execute` / `sql.executeBatch`.
enum OdbcE2eSqlDialect {
  sqlAnywhere,
  sqlServer,
  postgresql,
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
  if (driver.contains('ANYWHERE') || driver.contains('SYBASE') || driver.contains('SQLA')) {
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

/// Shared table name for coverage tests (unquoted; avoid reserved words).
const odbcE2eCoverageTableName = 'plug_agente_e2e_cov';

class OdbcE2eCoverageSql {
  OdbcE2eCoverageSql(this.dialect);

  /// Driver family used for literals and DDL.
  final OdbcE2eSqlDialect dialect;

  String get dropTableIfExists => 'DROP TABLE IF EXISTS $odbcE2eCoverageTableName';

  String get createTable => switch (dialect) {
    OdbcE2eSqlDialect.sqlAnywhere =>
      '''
CREATE TABLE $odbcE2eCoverageTableName (
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
CREATE TABLE $odbcE2eCoverageTableName (
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
CREATE TABLE $odbcE2eCoverageTableName (
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
INSERT INTO $odbcE2eCoverageTableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, '$code', $amt, DATE '$birthDate', TIMESTAMP '$ts', $active
)
''',
      OdbcE2eSqlDialect.sqlServer =>
        '''
INSERT INTO $odbcE2eCoverageTableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, N'$code', $amt, CAST('$birthDate' AS DATE), CAST('$ts' AS DATETIME2(3)), $active
)
''',
      OdbcE2eSqlDialect.sqlAnywhere =>
        '''
INSERT INTO $odbcE2eCoverageTableName (
  id, code, amt, birth_date, ts_col, is_active
) VALUES (
  $id, '$code', $amt, '$birthDate', '$ts', $active
)
''',
    };
  }

  String get multiResultProbe =>
      '''
SELECT id, code, amt FROM $odbcE2eCoverageTableName WHERE id = 1;
SELECT COUNT(*) AS row_count FROM $odbcE2eCoverageTableName;
''';

  String updateAmtById(int id, double delta) =>
      'UPDATE $odbcE2eCoverageTableName SET amt = amt + $delta WHERE id = $id';

  String updateCodeById(int id, String code) =>
      "UPDATE $odbcE2eCoverageTableName SET code = '${code.replaceAll("'", "''")}' WHERE id = $id";

  String deleteById(int id) => 'DELETE FROM $odbcE2eCoverageTableName WHERE id = $id';

  String get countAll => 'SELECT COUNT(*) AS row_count FROM $odbcE2eCoverageTableName';

  /// Single-row probe for batch SELECT coverage (same shape for SA / SQL Server / PostgreSQL).
  String selectIdCodeAmtById(int id) => 'SELECT id, code, amt FROM $odbcE2eCoverageTableName WHERE id = $id';
}
