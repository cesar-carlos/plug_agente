import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/application/rpc/sql_execute_materialized_result_policy.dart';
import 'package:plug_agente/application/rpc/sql_execute_params_reader.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/application/rpc/sql_options_resolver.dart';
import 'package:plug_agente/application/rpc/sql_pagination_resolver.dart';
import 'package:plug_agente/application/rpc/sql_rpc_client_token_gate.dart';
import 'package:plug_agente/application/rpc/sql_rpc_db_streaming_executor.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_materialized_streaming_executor.dart';
import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/application/rpc/sql_rpc_odbc_budget_runner.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart' show sqlStatementsForClientTokenAuthorization;
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:uuid/uuid.dart';

/// Handles `sql.execute` RPC requests.
class SqlExecuteHandler {
  SqlExecuteHandler({
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    required SqlRpcClientTokenGate clientTokenGate,
    required SqlRpcOdbcBudgetRunner odbcBudgetRunner,
    required SqlRpcDbStreamingExecutor dbStreamingExecutor,
    required SqlRpcMaterializedStreamingExecutor materializedStreamingExecutor,
    required Duration sqlExecuteTotalBudget,
    SqlDbStreamingAutoPolicy? dbStreamingAutoPolicy,
    SqlExecuteMaterializedResultPolicy? materializedResultPolicy,
    IDeprecationMetricsCollector? deprecationMetrics,
    IRpcDispatchMetricsCollector? dispatchMetrics,
  }) : _normalizerService = normalizerService,
       _uuid = uuid,
       _featureFlags = featureFlags,
       _support = support,
       _clientTokenGate = clientTokenGate,
       _odbcBudgetRunner = odbcBudgetRunner,
       _dbStreamingExecutor = dbStreamingExecutor,
       _materializedStreamingExecutor = materializedStreamingExecutor,
       _dbStreamingAutoPolicy = dbStreamingAutoPolicy ?? SqlDbStreamingAutoPolicy(),
       _materializedResultPolicy = materializedResultPolicy ?? const SqlExecuteMaterializedResultPolicy(),
       _sqlExecuteTotalBudgetDuration = sqlExecuteTotalBudget,
       _deprecationMetrics = deprecationMetrics,
       _dispatchMetrics = dispatchMetrics;

  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;
  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final SqlRpcClientTokenGate _clientTokenGate;
  final SqlRpcOdbcBudgetRunner _odbcBudgetRunner;
  final SqlRpcDbStreamingExecutor _dbStreamingExecutor;
  final SqlRpcMaterializedStreamingExecutor _materializedStreamingExecutor;
  final SqlDbStreamingAutoPolicy _dbStreamingAutoPolicy;
  final SqlExecuteMaterializedResultPolicy _materializedResultPolicy;
  final Duration _sqlExecuteTotalBudgetDuration;
  final IDeprecationMetricsCollector? _deprecationMetrics;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final SqlExecuteResultMapper _resultMapper = const SqlExecuteResultMapper();

  Future<RpcResponse> handleSqlExecute(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    IRpcStreamEmitter? streamEmitter,
  }) async {
    if (request.params is! Map<String, dynamic>) {
      return _support.invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final paramReader = SqlExecuteParamsReader(params);
    final sql = paramReader.sql;
    final maxRows = resolveMaxRows(params, limits.maxRows);
    // Always bound hub-originated sql.execute so a slow ODBC call cannot hold the
    // UI isolate and RPC slots indefinitely when the stage-timeout flag is off.
    final deadline = DateTime.now().add(_sqlExecuteTotalBudgetDuration);

    if (sql == null || sql.isEmpty) {
      return _support.invalidParams(request, 'sql is required');
    }
    final options = paramReader.options;
    if (options?['preserve_sql'] == true) {
      _deprecationMetrics?.recordPreserveSqlUsage(
        requestId: request.id?.toString(),
        method: request.method,
      );
    }
    final sqlHandlingModeResolution = resolveSqlHandlingMode(params);
    if (sqlHandlingModeResolution.hasError) {
      return _support.invalidParams(
        request,
        sqlHandlingModeResolution.errorMessage!,
      );
    }
    final sqlHandlingMode = sqlHandlingModeResolution.sqlHandlingMode!;
    final paginationResolution = sqlHandlingMode == SqlHandlingMode.preserve
        ? const ResolvedPagination()
        : resolvePagination(
            params,
            sql,
            maxRows,
            negotiatedExtensions,
          );
    if (paginationResolution.hasError) {
      return _support.invalidParams(request, paginationResolution.errorMessage!);
    }
    final pagination = paginationResolution.pagination;
    final multiResultRequested = resolveMultiResult(params);
    final requestParameters = paramReader.boundParams;
    final database = paramReader.database;
    final requestedTimeoutMs = resolveRequestedTimeoutMs(params);

    if (multiResultRequested && requestParameters != null && requestParameters.isNotEmpty) {
      return _support.invalidParams(
        request,
        'multi_result is not supported with named parameters',
      );
    }
    if (multiResultRequested && pagination != null) {
      return _support.invalidParams(
        request,
        'multi_result cannot be combined with pagination',
      );
    }

    final idempotencyKey = paramReader.idempotencyKey;
    final idempotencyFingerprint = await resolveIdempotencyFingerprintIfEnabled(
      enabled: _featureFlags.enableSocketIdempotency,
      idempotencyKey: idempotencyKey,
      method: request.method,
      params: params,
    );
    final idempotentEarly = await _support.consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint ?? '',
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    final authDenied = await _clientTokenGate.enforce(
      request: request,
      clientToken: clientToken,
      sqlStatements: multiResultRequested ? sqlStatementsForClientTokenAuthorization(sql) : [sql],
      investigationSqlOnDeny: sql,
      requestDatabase: database,
      deadline: deadline,
      deduplicateEquivalentSql: multiResultRequested,
      skipEmptyAfterTrim: multiResultRequested,
    );
    if (authDenied != null) {
      return authDenied;
    }

    final validation = SqlValidator.validateSqlForExecution(
      sql,
      allowMultipleStatements: multiResultRequested,
    );
    if (validation.isError()) {
      final failure = validation.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final queryRequest = QueryRequest(
      id: _uuid.v4(),
      agentId: agentId,
      query: sql,
      parameters: requestParameters,
      timestamp: DateTime.now(),
      pagination: pagination,
      expectMultipleResults: multiResultRequested,
      sqlHandlingMode: sqlHandlingMode,
      sourceRpcRequestId: request.id?.toString(),
    );

    return _support.runIdempotentExecution(
      request: request,
      idempotencyKey: idempotencyKey,
      idempotencyFingerprint: idempotencyFingerprint ?? '',
      idempotentCachePrefetched: true,
      execute: () async {
        final prefersDbStreaming = _dbStreamingAutoPolicy.prefersDbStreamingOverMaterialized(
          featureFlags: _featureFlags,
          queryRequest: queryRequest,
          sql: sql,
          negotiatedExtensions: negotiatedExtensions,
          preferDbStreaming: options?['prefer_db_streaming'] == true,
          effectiveMaxRows: maxRows,
          limits: limits,
        );

        final explicitPreferDbStreaming = options?['prefer_db_streaming'] == true;
        final autoPreferDbStreaming =
            isStreamingResultsNegotiated(negotiatedExtensions) &&
            maxRows > ConnectionConstants.sqlExecuteMaterializedMaxRows;
        final preferDbStreamingForAttempt = explicitPreferDbStreaming || autoPreferDbStreaming;

        var streamingTry = await _dbStreamingExecutor.tryStreamingFromDb(
          request,
          queryRequest,
          sql,
          request.isNotification ? null : streamEmitter,
          limits: limits,
          deadline: deadline,
          timeoutMs: requestedTimeoutMs,
          negotiatedExtensions: negotiatedExtensions,
          preferDbStreaming: preferDbStreamingForAttempt,
          effectiveMaxRows: maxRows,
          clientToken: clientToken,
          database: database,
        );
        if (!streamingTry.succeeded && !explicitPreferDbStreaming && (prefersDbStreaming || autoPreferDbStreaming)) {
          streamingTry = await _dbStreamingExecutor.tryStreamingFromDb(
            request,
            queryRequest,
            sql,
            request.isNotification ? null : streamEmitter,
            limits: limits,
            deadline: deadline,
            timeoutMs: requestedTimeoutMs,
            negotiatedExtensions: negotiatedExtensions,
            preferDbStreaming: true,
            effectiveMaxRows: maxRows,
            clientToken: clientToken,
            database: database,
          );
        }
        final streamingFromDbResponse = streamingTry.response;
        if (streamingFromDbResponse != null) {
          return streamingFromDbResponse;
        }

        if (supportsStreamingChunks(negotiatedExtensions)) {
          final materializedFallbackGuard = _materializedResultPolicy.rejectIfMaterializedOdbcFallbackUnsafe(
            effectiveMaxRows: maxRows,
            limits: limits,
            negotiatedExtensions: negotiatedExtensions,
            prefersDbStreaming: prefersDbStreaming,
            requestId: request.id?.toString(),
            dbStreamingSkipReason: streamingTry.skipReason,
          );
          if (materializedFallbackGuard.isError()) {
            _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('materialized_odbc_fallback_rejected');
            final domainFailure = materializedFallbackGuard.exceptionOrNull()! as domain.Failure;
            final rpcError = FailureToRpcErrorMapper.map(
              domainFailure,
              instance: request.id?.toString(),
              useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
            );
            return RpcResponse.error(id: request.id, error: rpcError);
          }
        }

        if (prefersDbStreaming) {
          _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('db_streaming_unavailable_fallback');
        }

        final result = await _odbcBudgetRunner.executeQuery(
          queryRequest,
          database: database,
          requestId: request.id?.toString(),
          deadline: deadline,
          timeoutMs: requestedTimeoutMs,
          effectiveMaxRows: maxRows,
          transportLimits: limits,
          negotiatedExtensions: negotiatedExtensions,
        );

        return result.fold<Future<RpcResponse>>(
          (QueryResponse queryResponse) async {
            final normalized = queryRequest.sqlHandlingMode == SqlHandlingMode.preserve
                ? queryResponse
                : await _normalizerService.normalizeAsync(queryResponse);

            final hasMultiResultSets = normalized.resultSets.isNotEmpty;
            var truncatedMulti = normalized;
            if (hasMultiResultSets) {
              truncatedMulti = _resultMapper.applyMaxRowsToMultiResultSets(
                normalized,
                maxRows,
              );
            }

            final limitedRows = hasMultiResultSets
                ? truncatedMulti.data
                : truncateSqlResultRows(normalized.data, maxRows);
            final wasTruncated = hasMultiResultSets
                ? _resultMapper.multiResultSetsWereTruncated(
                    normalized,
                    truncatedMulti,
                  )
                : limitedRows.length != normalized.data.length;
            final responseForWire = hasMultiResultSets ? truncatedMulti : normalized;
            final avoidMaterializedStreaming = _dbStreamingAutoPolicy.prefersDbStreamingOverMaterialized(
              featureFlags: _featureFlags,
              queryRequest: queryRequest,
              sql: sql,
              negotiatedExtensions: negotiatedExtensions,
              preferDbStreaming: options?['prefer_db_streaming'] == true,
              effectiveMaxRows: maxRows,
              limits: limits,
            );
            final useStreaming =
                _featureFlags.enableSocketStreamingChunks &&
                streamEmitter != null &&
                !request.isNotification &&
                pagination == null &&
                !responseForWire.hasMultiResult &&
                limitedRows.length > limits.streamingRowThreshold &&
                !avoidMaterializedStreaming;

            if (!useStreaming && avoidMaterializedStreaming && limitedRows.length > limits.streamingRowThreshold) {
              _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('materialized_streaming_avoided');
            }

            if (useStreaming) {
              final streamingFallbackGuard = _materializedResultPolicy.rejectIfMaterializedStreamingFallbackUnsafe(
                rowCount: limitedRows.length,
                limits: limits,
                negotiatedExtensions: negotiatedExtensions,
                requestId: request.id?.toString(),
              );
              if (streamingFallbackGuard.isError()) {
                _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('materialized_streaming_fallback_rejected');
                final domainFailure = streamingFallbackGuard.exceptionOrNull()! as domain.Failure;
                final rpcError = FailureToRpcErrorMapper.map(
                  domainFailure,
                  instance: request.id?.toString(),
                  useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                );
                return RpcResponse.error(id: request.id, error: rpcError);
              }

              return _materializedStreamingExecutor.streamMaterializedResult(
                request: request,
                queryRequest: queryRequest,
                normalized: responseForWire,
                limitedRows: limitedRows,
                effectiveMaxRows: maxRows,
                wasTruncated: wasTruncated,
                limits: limits,
                streamEmitter: streamEmitter,
              );
            }

            final resultData = _resultMapper.buildExecuteResultData(
              responseForWire,
              startedAt: queryRequest.timestamp,
              finishedAt: responseForWire.timestamp,
              limitedRows: limitedRows,
              wasTruncated: wasTruncated,
              sqlHandlingMode: queryRequest.sqlHandlingMode,
              effectiveMaxRows: maxRows,
              forceMultiResultEnvelope: multiResultRequested,
            );

            final rpcResponse = RpcResponse.success(
              id: request.id,
              result: resultData,
            );
            _dispatchMetrics?.recordSqlExecuteMaterializedResponse();
            return rpcResponse;
          },
          (Exception failure) async {
            final domainFailure = failure as domain.Failure;
            if (domainFailure.context['reason'] == RpcSqlBudgetConstants.materializedResultTooLargeReason) {
              _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('materialized_result_too_large');
            }
            final rpcError = FailureToRpcErrorMapper.map(
              domainFailure,
              instance: request.id?.toString(),
              useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
            );
            return RpcResponse.error(id: request.id, error: rpcError);
          },
        );
      },
    );
  }
}
