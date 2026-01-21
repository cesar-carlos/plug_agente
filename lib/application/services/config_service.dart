import 'package:result_dart/result_dart.dart';

import '../../domain/entities/config.dart';
import '../../domain/value_objects/database_driver.dart';
import '../validation/config_validator.dart';

class ConfigService {
  final ConfigValidator _validator;

  ConfigService(this._validator);

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
    final buffer = StringBuffer('DRIVER={SQL Server};');
    buffer.write('SERVER=${config.host},${config.port};');
    buffer.write('DATABASE=${config.databaseName};');
    buffer.write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    return buffer.toString();
  }

  String _buildPostgreSqlConnectionString(Config config) {
    final buffer = StringBuffer('DRIVER={PostgreSQL Unicode};');
    buffer.write('SERVER=${config.host};');
    buffer.write('PORT=${config.port};');
    buffer.write('DATABASE=${config.databaseName};');
    buffer.write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    return buffer.toString();
  }

  String _buildSqlAnywhereConnectionString(Config config) {
    final buffer = StringBuffer('DRIVER={${config.odbcDriverName}};');
    buffer.write('UID=${config.username}');
    if (config.password != null) {
      buffer.write(';PWD=${config.password}');
    }
    buffer.write(';DBN=${config.databaseName};');
    buffer.write('HOST=${config.host};');
    buffer.write('PORT=${config.port}');
    return buffer.toString();
  }
}
