import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

/// Coordinates transport-level connection requests against the active
/// [ITransportClient] and exposes database connectivity probes.
///
/// Connect retries intentionally live in two upper layers only:
///   1. The Socket.IO client itself (transport-level reconnect).
///   2. `ConnectionProvider._recoverConnection` (burst + persistent retry).
///
/// Wrapping `connect` here in a generic `IRetryManager` would multiply attempts
/// (3x retry-manager * 3x burst = up to 9x) and delay user feedback by ~30s on
/// the first failed attempt, so this layer just delegates.
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
  }) {
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
