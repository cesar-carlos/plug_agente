import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_types.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:result_dart/result_dart.dart';

final class OdbcBatchConnectionPhase {
  OdbcBatchConnectionPhase({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcConnectionOptionsResolver optionsResolver,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required BatchEnsureInitialized ensureInitialized,
    required BatchResolveActiveConfig resolveActiveConfig,
    required BatchBuildDatabaseConfig buildDatabaseConfig,
    required BatchResolveConnectionString resolveConnectionString,
    required BatchInfrastructureFailureRecorder recordInfrastructureFailure,
  }) : _connectionManager = connectionManager,
       _optionsResolver = optionsResolver,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _ensureInitialized = ensureInitialized,
       _resolveActiveConfig = resolveActiveConfig,
       _buildDatabaseConfig = buildDatabaseConfig,
       _resolveConnectionString = resolveConnectionString,
       _recordInfrastructureFailure = recordInfrastructureFailure;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final BatchEnsureInitialized _ensureInitialized;
  final BatchResolveActiveConfig _resolveActiveConfig;
  final BatchBuildDatabaseConfig _buildDatabaseConfig;
  final BatchResolveConnectionString _resolveConnectionString;
  final BatchInfrastructureFailureRecorder _recordInfrastructureFailure;

  Future<void> releaseBatchConnection(BatchExecutionContext context) async {
    if (context.ownedConnection) {
      final directLease = context.directLease;
      if (directLease == null) {
        await _connectionManager.disconnectOwnedConnectionSafely(
          context.connectionId,
          operation: 'batch_direct_disconnect',
        );
        return;
      }

      await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
        connectionId: context.connectionId,
        directLease: directLease,
        operation: 'batch_direct_disconnect',
      );
      return;
    }
    await _connectionManager.releaseConnectionSafely(context.connectionId);
  }

  Future<Result<BatchExecutionContext>> prepareBatchExecutionContext({
    required String? database,
    required Duration? timeout,
    required bool useOwnedConnection,
    required bool allowNativeCompatibleTransaction,
    required List<SqlCommand> commands,
    required String batchSqlPreview,
    String? sourceRpcRequestId,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      final failure = initResult.exceptionOrNull();
      if (failure != null) {
        return Failure(failure);
      }
      return Failure(
        domain.ConnectionFailure('Failed to initialize ODBC for batch'),
      );
    }

    final configResult = await _resolveActiveConfig();
    if (configResult.isError()) {
      return Failure(
        domain.ConfigurationFailure(
          'Failed to load database configuration for batch execution',
        ),
      );
    }

    final config = configResult.getOrNull()!;
    final localConfig = _buildDatabaseConfig(config);
    final connectionString = _resolveConnectionString(
      config,
      localConfig,
      databaseOverride: database,
    );
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    final useNativeCompatibleTransaction =
        allowNativeCompatibleTransaction &&
        _nativeCompatiblePolicy.shouldUseTransactionalBatch(
          databaseType: localConfig.databaseType,
          commands: commands,
        );

    final isTransactional = useOwnedConnection || allowNativeCompatibleTransaction;
    if (useOwnedConnection || (allowNativeCompatibleTransaction && !useNativeCompatibleTransaction)) {
      final leaseResult = await _connectionManager.acquireDirectLease(
        operation: 'batch_transaction',
        deadline: deadline,
      );
      if (leaseResult.isError()) {
        final err = leaseResult.exceptionOrNull()!;
        _recordInfrastructureFailure(
          originalSql: batchSqlPreview,
          errorMessage: OdbcErrorInspector.message(err),
          rpcRequestId: sourceRpcRequestId,
        );
        return Failure(err);
      }
      final directLease = leaseResult.getOrThrow();
      final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: isTransactional
            ? _optionsResolver.transactionalForTimeout(remainingTimeout).toOdbcConnectionOptions()
            : _optionsResolver.forTimeout(remainingTimeout).toOdbcConnectionOptions(),
      );
      return connectResult.fold(
        (connection) {
          return Success(
            BatchExecutionContext(
              connectionId: connection.id,
              connectionString: connectionString,
              deadline: deadline,
              directLease: directLease,
              ownedConnection: true,
            ),
          );
        },
        (error) {
          directLease.release();
          _recordInfrastructureFailure(
            originalSql: batchSqlPreview,
            errorMessage: OdbcErrorInspector.message(error),
            rpcRequestId: sourceRpcRequestId,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_direct',
              context: {
                'operation': 'batch_execute',
                'transaction': true,
              },
            ),
          );
        },
      );
    }

    final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
    final connectionOptions = isTransactional
        ? _optionsResolver.transactionalForTimeout(remainingTimeout)
        : _optionsResolver.forTimeout(remainingTimeout);
    final poolResult = useNativeCompatibleTransaction
        ? await _connectionManager.acquireNativeCompatiblePooledConnection(
            connectionString,
            leaseFallbackOptions: connectionOptions,
            deadline: deadline,
            context: {'operation': 'batch_transaction_native_compatible'},
          )
        : await _connectionManager.acquirePooledConnection(
            connectionString,
            options: connectionOptions,
            deadline: deadline,
            context: {'operation': 'batch_execute'},
          );
    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      final failure = error is domain.Failure
          ? error
          : OdbcFailureMapper.mapPoolError(
              error,
              operation: 'acquire_connection',
              context: {'operation': 'batch_execute'},
            );
      _recordInfrastructureFailure(
        originalSql: batchSqlPreview,
        errorMessage: OdbcErrorInspector.message(error),
        rpcRequestId: sourceRpcRequestId,
      );
      return Failure(
        failure,
      );
    }

    return Success(
      BatchExecutionContext(
        connectionId: poolResult.getOrNull()!,
        connectionString: connectionString,
        deadline: deadline,
        nativeCompatibleAcquire: useNativeCompatibleTransaction,
      ),
    );
  }
}
