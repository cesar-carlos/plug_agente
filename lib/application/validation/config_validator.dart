import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class ConfigValidator {
  Result<bool> validate(Config config) {
    final errors = <String>[];

    if (config.id.isEmpty) {
      errors.add('ID cannot be empty');
    }

    if (config.driverName.isEmpty) {
      errors.add('Driver name cannot be empty');
    }

    if (config.connectionString.isEmpty) {
      errors.add('Connection string cannot be empty');
    }

    if (config.username.isEmpty) {
      errors.add('Username cannot be empty');
    }

    if (config.databaseName.isEmpty) {
      errors.add('Database name cannot be empty');
    }

    if (config.host.isEmpty) {
      errors.add('Host cannot be empty');
    }

    if (config.port <= 0) {
      errors.add('Port must be greater than 0');
    }

    if (errors.isNotEmpty) {
      return Failure(domain.ValidationFailure(errors.join(', ')));
    }

    return const Success(true);
  }
}
