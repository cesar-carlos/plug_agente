import 'package:result_dart/result_dart.dart';
import '../../domain/entities/config.dart';
import '../validation/config_validator.dart';

class ConfigService {
  final ConfigValidator _validator;

  ConfigService(this._validator);

  Future<Result<bool>> validateConfig(Config config) async {
    return _validator.validate(config);
  }

  String generateConnectionString(Config config) {
    switch (config.driverName.toLowerCase()) {
      case 'sql server':
        return 'DRIVER={SQL Server};SERVER=${config.host},${config.port};DATABASE=${config.databaseName};UID=${config.username}${config.password != null ? ';PWD=${config.password}' : ''}';
      case 'postgresql':
      case 'postgres':
        return 'DRIVER={PostgreSQL Unicode};SERVER=${config.host};PORT=${config.port};DATABASE=${config.databaseName};UID=${config.username}${config.password != null ? ';PWD=${config.password}' : ''}';
      case 'sql anywhere':
        return 'DRIVER={SQL Anywhere 17};UID=${config.username}${config.password != null ? ';PWD=${config.password}' : ''};DBN=${config.databaseName};HOST=${config.host};PORT=${config.port}';
      default:
        return '';
    }
  }
}
