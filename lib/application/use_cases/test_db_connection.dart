import 'package:result_dart/result_dart.dart';

import '../services/connection_service.dart';
import '../../domain/errors/failures.dart' as domain;

class TestDbConnection {
  final ConnectionService _service;

  TestDbConnection(this._service);

  Future<Result<bool>> call(String connectionString) async {
    if (connectionString.isEmpty) {
      return Failure(
        domain.ValidationFailure('Connection string cannot be empty'),
      );
    }

    return await _service.testConnection(connectionString);
  }
}
