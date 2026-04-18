import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class ConnectToHub {
  ConnectToHub(this._service);
  final ConnectionService _service;

  Future<Result<void>> call(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (agentId.isEmpty) {
      return Failure(domain.ValidationFailure('Agent ID cannot be empty'));
    }

    if (authToken == null || authToken.trim().isEmpty) {
      return Failure(
        domain.ConfigurationFailure(
          'Authentication token required to connect to the hub',
        ),
      );
    }

    return _service.connect(serverUrl, agentId, authToken: authToken);
  }
}
