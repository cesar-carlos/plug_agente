import 'package:result_dart/result_dart.dart';

import '../../domain/repositories/i_transport_client.dart';
import '../../domain/repositories/i_database_gateway.dart';
import '../../domain/errors/failures.dart' as domain;

class ConnectionService {
  final ITransportClient _transportClient;
  final IDatabaseGateway _databaseGateway;

  ConnectionService(this._transportClient, this._databaseGateway);

  Future<Result<void>> connect(String serverUrl, String agentId, {String? authToken}) async {
    try {
      final connectionResult = await _transportClient.connect(serverUrl, agentId, authToken: authToken);
      return connectionResult;
    } catch (e) {
      return Failure(domain.ConnectionFailure('Failed to connect to hub: $e'));
    }
  }

  Future<Result<bool>> testConnection(String connectionString) async {
    try {
      return await _databaseGateway.testConnection(connectionString);
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to test database connection: $e'));
    }
  }
}
