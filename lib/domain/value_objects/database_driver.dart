enum DatabaseDriver {
  sqlServer('SQL Server'),
  postgreSQL('PostgreSQL'),
  sqlAnywhere('SQL Anywhere'),
  unknown('Unknown')
  ;

  const DatabaseDriver(this.displayName);

  final String displayName;

  static DatabaseDriver fromString(String driverName) {
    switch (driverName.toLowerCase()) {
      case 'sql server':
      case 'microsoft sql server':
      case 'mssql':
        return DatabaseDriver.sqlServer;
      case 'postgresql':
      case 'postgres':
        return DatabaseDriver.postgreSQL;
      case 'sql anywhere':
      case 'sybase sql anywhere':
      case 'sybase anywhere':
        return DatabaseDriver.sqlAnywhere;
      default:
        return DatabaseDriver.unknown;
    }
  }

  @override
  String toString() => displayName;
}
