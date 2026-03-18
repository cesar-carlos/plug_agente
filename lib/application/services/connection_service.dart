import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class ConnectionService {
  ConnectionService(
    this._transportClientGetter,
    this._databaseGateway,
  );
  final ITransportClient Function() _transportClientGetter;
  final IDatabaseGateway _databaseGateway;

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    return _transportClientGetter().connect(
      serverUrl,
      agentId,
      authToken: authToken,
    );
  }

  Future<Result<bool>> testConnection(String connectionString) async {
    return _databaseGateway.testConnection(connectionString);
  }
}
