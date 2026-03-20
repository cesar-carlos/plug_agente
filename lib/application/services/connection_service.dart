import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class ConnectionService {
  ConnectionService(
    this._transportClientGetter,
    this._databaseGateway,
    this._retryManager,
  );
  final ITransportClient Function() _transportClientGetter;
  final IDatabaseGateway _databaseGateway;
  final IRetryManager _retryManager;

  static const int _connectMaxAttempts = 3;
  static const int _connectInitialDelayMs = 500;

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    final result = await _retryManager.execute<Object>(
      () async {
        final r = await _transportClientGetter().connect(
          serverUrl,
          agentId,
          authToken: authToken,
        );
        return r.fold(
          (_) => const Success(unit),
          Failure.new,
        );
      },
      maxAttempts: _connectMaxAttempts,
      initialDelayMs: _connectInitialDelayMs,
    );
    return result.fold(
      (_) => const Success(unit),
      Failure.new,
    );
  }

  Future<Result<bool>> testConnection(String connectionString) async {
    return _databaseGateway.testConnection(connectionString);
  }
}
