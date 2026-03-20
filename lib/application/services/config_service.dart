import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/core/constants/odbc_drivers.dart';
import 'package:plug_agente/core/constants/sql_anywhere_connection_string.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:result_dart/result_dart.dart';

class ConfigService {
  ConfigService(this._validator);
  final ConfigValidator _validator;

  Future<Result<bool>> validateConfig(Config config) async {
    return _validator.validate(config);
  }

  String generateConnectionString(Config config) {
    final driver = DatabaseDriver.fromString(config.driverName);

    return switch (driver) {
      DatabaseDriver.sqlServer => _buildSqlServerConnectionString(config),
      DatabaseDriver.postgreSQL => _buildPostgreSqlConnectionString(config),
      DatabaseDriver.sqlAnywhere => _buildSqlAnywhereConnectionString(config),
      DatabaseDriver.unknown => '',
    };
  }

  String _buildSqlServerConnectionString(Config config) {
    final driver = config.odbcDriverName.isNotEmpty ? config.odbcDriverName : 'ODBC Driver 17 for SQL Server';
    final buffer = StringBuffer('DRIVER={$driver};')
      ..write('SERVER=${config.host},${config.port};')
      ..write('DATABASE=${config.databaseName};')
      ..write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    return buffer.toString();
  }

  String _buildPostgreSqlConnectionString(Config config) {
    final driver = config.odbcDriverName.isNotEmpty ? config.odbcDriverName : OdbcDrivers.postgresqlUnicode;
    final buffer = StringBuffer('DRIVER={$driver};')
      ..write('SERVER=${config.host};')
      ..write('PORT=${config.port};')
      ..write('DATABASE=${config.databaseName};')
      ..write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    return buffer.toString();
  }

  String _buildSqlAnywhereConnectionString(Config config) {
    return SqlAnywhereConnectionString.build(
      driverName: config.odbcDriverName,
      username: config.username,
      database: config.databaseName,
      host: config.host,
      port: config.port,
      password: config.password,
    );
  }
}
