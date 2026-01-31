import 'package:plug_agente/application/validation/config_validator.dart';
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
    final buffer = StringBuffer('DRIVER={SQL Server};')
      ..write('SERVER=${config.host},${config.port};')
      ..write('DATABASE=${config.databaseName};')
      ..write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    return buffer.toString();
  }

  String _buildPostgreSqlConnectionString(Config config) {
    final buffer = StringBuffer('DRIVER={PostgreSQL Unicode};')
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
    final buffer = StringBuffer('DRIVER={${config.odbcDriverName}};')
      ..write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    buffer
      ..write(';DBN=${config.databaseName};')
      ..write('HOST=${config.host};')
      ..write('PORT=${config.port}');
    return buffer.toString();
  }
}
