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
    return _transportClient.connect(
      serverUrl,
      agentId,
      authToken: authToken,
    );
  }

  Future<Result<bool>> testConnection(String connectionString) async {
    return _databaseGateway.testConnection(connectionString);
  }
}
