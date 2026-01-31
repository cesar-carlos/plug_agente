import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class ConnectionService {
  ConnectionService(this._transportClient, this._databaseGateway);
  final ITransportClient _transportClient;
  final IDatabaseGateway _databaseGateway;

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    try {
      final connectionResult = await _transportClient.connect(
        serverUrl,
        agentId,
        authToken: authToken,
      );
      return connectionResult;
    } on Exception catch (e) {
      return Failure(domain.ConnectionFailure('Failed to connect to hub: $e'));
    }
  }

  Future<Result<bool>> testConnection(String connectionString) async {
    try {
      return await _databaseGateway.testConnection(connectionString);
    } on Exception catch (e) {
      return Failure(
        domain.DatabaseFailure('Failed to test database connection: $e'),
      );
    }
  }
}
