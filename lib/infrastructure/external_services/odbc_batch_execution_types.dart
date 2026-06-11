import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

typedef BatchEnsureInitialized = Future<Result<void>> Function();
typedef BatchResolveActiveConfig = Future<Result<Config>> Function();
typedef BatchBuildDatabaseConfig = DatabaseConfig Function(Config config);
typedef BatchResolveConnectionString =
    String Function(
      Config config,
      DatabaseConfig databaseConfig, {
      String? databaseOverride,
    });
typedef BatchInfrastructureFailureRecorder =
    void Function({
      required String originalSql,
      required String errorMessage,
      String? rpcRequestId,
      String method,
    });
typedef BatchSqlExecutionFailureRecorder =
    void Function({
      required QueryRequest request,
      required OdbcPreparedQueryExecution preparedExecution,
      required String errorMessage,
      required bool executedInDb,
      String method,
    });

class BatchExecutionContext {
  const BatchExecutionContext({
    required this.connectionId,
    required this.connectionString,
    required this.deadline,
    this.directLease,
    this.ownedConnection = false,
    this.nativeCompatibleAcquire = false,
  });

  final String connectionId;
  final String connectionString;
  final DateTime? deadline;
  final DirectOdbcConnectionLease? directLease;
  final bool ownedConnection;
  final bool nativeCompatibleAcquire;
}

class BatchConnectionState {
  BatchConnectionState(this.connectionId);

  String? connectionId;
}
