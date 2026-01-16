import 'package:result_dart/result_dart.dart';

import '../services/connection_service.dart';
import '../../domain/errors/failures.dart' as domain;

class ConnectToHub {
  final ConnectionService _service;

  ConnectToHub(this._service);

  Future<Result<void>> call(String serverUrl, String agentId, {String? authToken}) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (agentId.isEmpty) {
      return Failure(domain.ValidationFailure('Agent ID cannot be empty'));
    }

    return await _service.connect(serverUrl, agentId, authToken: authToken);
  }
}
