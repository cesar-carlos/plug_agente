import 'package:plug_agente/application/validation/input_validators.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class ConfigValidator {
  ConfigValidator();

  Result<bool> validate(Config config) {
    final errors = <String>[];

    final idResult = _validateId(config.id);
    if (idResult.isError()) {
      errors.add('ID: ${(idResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid ID'}');
    }

    final driverResult = _validateDriverName(config.driverName);
    if (driverResult.isError()) {
      errors.add(
        'Driver name: ${(driverResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid driver name'}',
      );
    }

    final connResult = _validateConnectionString(config.connectionString);
    if (connResult.isError()) {
      errors.add(
        'Connection string: ${(connResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid connection string'}',
      );
    }

    final userResult = _validateUsername(config.username);
    if (userResult.isError()) {
      errors.add('Username: ${(userResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid username'}');
    }

    final dbResult = _validateDatabaseName(config.databaseName);
    if (dbResult.isError()) {
      errors.add(
        'Database name: ${(dbResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid database name'}',
      );
    }

    final hostResult = _validateHost(config.host);
    if (hostResult.isError()) {
      errors.add('Host: ${(hostResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid host'}');
    }

    final portResult = _validatePort(config.port);
    if (portResult.isError()) {
      errors.add('Port: ${(portResult.exceptionOrNull() as domain.Failure?)?.message ?? 'Invalid port'}');
    }

    if (errors.isNotEmpty) {
      return Failure(domain.ValidationFailure(errors.join('; ')));
    }

    return const Success(true);
  }

  Result<String> _validateId(String id) {
    return InputValidators.nonEmptyString(
      id,
      minLength: 1,
    ).map((_) => id);
  }

  Result<String> _validateDriverName(String driverName) {
    return InputValidators.nonEmptyString(
      driverName,
      minLength: 1,
    ).map((_) => driverName);
  }

  Result<String> _validateConnectionString(String connectionString) {
    return InputValidators.nonEmptyString(
      connectionString,
      minLength: 1,
    ).map((_) => connectionString);
  }

  Result<String> _validateUsername(String username) {
    return InputValidators.nonEmptyString(
      username,
      minLength: 1,
    ).map((_) => username);
  }

  Result<String> _validateDatabaseName(String databaseName) {
    return InputValidators.databaseName(
      databaseName,
    ).map((_) => databaseName);
  }

  Result<String> _validateHost(String host) {
    final hostnameResult = InputValidators.hostname(host);
    if (hostnameResult.isSuccess()) {
      return hostnameResult;
    }

    final ipv4Result = InputValidators.ipv4(host);
    if (ipv4Result.isSuccess()) {
      return ipv4Result;
    }

    return Failure(
      domain.ValidationFailure('Host must be a valid hostname or IPv4 address'),
    );
  }

  Result<int> _validatePort(int port) {
    return InputValidators.port(port);
  }
}
