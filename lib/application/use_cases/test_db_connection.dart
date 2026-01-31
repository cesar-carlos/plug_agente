import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class TestDbConnection {
  TestDbConnection(this._service);
  final ConnectionService _service;

  Future<Result<bool>> call(String connectionString) async {
    if (connectionString.isEmpty) {
      return Failure(
        domain.ValidationFailure('Connection string cannot be empty'),
      );
    }

    return _service.testConnection(connectionString);
  }
}
