import 'package:plug_agente/application/ports/i_playground_db_connection_gateway.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:result_dart/result_dart.dart';

class ConnectionProviderPlaygroundDbGateway implements IPlaygroundDbConnectionGateway {
  ConnectionProviderPlaygroundDbGateway(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  @override
  Future<Result<bool>> testConnection(String connectionString) {
    return _connectionProvider.testDbConnection(
      connectionString,
      recordGlobalError: false,
    );
  }

  @override
  void syncConnectionIndicator(bool connected) {
    _connectionProvider.setDbConnectionIndicator(connected);
  }
}
