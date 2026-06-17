import 'dart:async';

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/mappers/sql_command_wire_mapper.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_rpc_client_token_gate.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/application/use_cases/validate_sql_batch.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

typedef SqlBatchSupportsPageOffsetPagination =
    bool Function(
      Map<String, dynamic> negotiatedExtensions,
    );

/// Handles `sql.executeBatch` RPC requests.
class SqlBatchHandler {
  SqlBatchHandler({
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    required SqlRpcClientTokenGate clientTokenGate,
    required Uuid uuid,
    required ExecuteSqlBatch executeSqlBatch,
    required Duration sqlBatchTotalBudget,
    required Duration batchExecutionStageBudget,
    ValidateSqlBatch? validateSqlBatch,
    SqlBatchSupportsPageOffsetPagination? supportsPageOffsetPagination,
    SqlCommandWireMapper? sqlCommandWireMapper,
  }) : _featureFlags = featureFlags,
       _support = support,
       _clientTokenGate = clientTokenGate,
       _uuid = uuid,
       _executeSqlBatch = executeSqlBatch,
       _validateSqlBatch = validateSqlBatch ?? const ValidateSqlBatch(),
       _sqlBatchTotalBudgetDuration = sqlBatchTotalBudget,
       _batchExecutionStageBudgetDuration = batchExecutionStageBudget,
       _supportsPageOffsetPagination = supportsPageOffsetPagination ?? _allowPageOffsetPagination,
       _sqlCommandWireMapper = sqlCommandWireMapper ?? const SqlCommandWireMapper();

  static bool _allowPageOffsetPagination(Map<String, dynamic> negotiatedExtensions) => true;

  static const int _sqlInvestigationBatchPreviewMaxChars = 8000;

  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final SqlRpcClientTokenGate _clientTokenGate;
  final Uuid _uuid;
  final ExecuteSqlBatch _executeSqlBatch;
  final ValidateSqlBatch _validateSqlBatch;
  final Duration _sqlBatchTotalBudgetDuration;
  final Duration _batchExecutionStageBudgetDuration;
  final SqlBatchSupportsPageOffsetPagination _supportsPageOffsetPagination;
  final SqlCommandWireMapper _sqlCommandWireMapper;

  Future<RpcResponse> handleSqlExecuteBatch(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) async {
    if (request.params is! Map<String, dynamic>) {
      return _support.invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final commandsJson = params['commands'] as List<dynamic>?;
    final deadline = DateTime.now().add(_sqlBatchTotalBudgetDuration);
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      final options = params['options'] as Map<String, dynamic>?;
      if (options?['page'] != null || options?['page_size'] != null) {
        return _support.invalidParams(
          request,
          'Negotiated protocol does not allow page-offset pagination',
        );
      }
    }

    if (commandsJson == null || commandsJson.isEmpty) {
      return _support.invalidParams(
        request,
        'commands is required and must not be empty',
      );
    }

    if (commandsJson.length > limits.maxBatchSize) {
      return _support.invalidParams(
        request,
        'commands exceeds negotiated limit: '
        '${commandsJson.length} > ${limits.maxBatchSize}',
      );
    }

    final idempotencyKey = params['idempotency_key'] as String?;
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

    final commandPlans = <BatchCommandExecutionPlan>[];
    for (var i = 0; i < commandsJson.length; i++) {
      final commandJson = commandsJson[i];
      if (commandJson is! Map<String, dynamic>) {
        return _support.invalidParams(request, 'commands[$i] must be an object');
      }

      final executionOrderRaw = commandJson['execution_order'];
      final executionOrder = executionOrderRaw != null ? jsonNonNegativeInt(executionOrderRaw) : null;
      if (executionOrderRaw != null && executionOrder == null) {
        return _support.invalidParams(
          request,
          'commands[$i].execution_order must be an integer >= 0',
        );
      }

      commandPlans.add(
        BatchCommandExecutionPlan(
          command: _sqlCommandWireMapper.fromJson(commandJson),
          requestIndex: i,
          executionOrder: executionOrder,
        ),
      );
    }

    commandPlans.sort((left, right) {
      final leftHasExplicitOrder = left.executionOrder != null;
      final rightHasExplicitOrder = right.executionOrder != null;

      if (leftHasExplicitOrder && rightHasExplicitOrder) {
        final orderCompare = left.executionOrder!.compareTo(
          right.executionOrder!,
        );
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.requestIndex.compareTo(right.requestIndex);
      }

      if (leftHasExplicitOrder && !rightHasExplicitOrder) {
        return -1;
      }
      if (!leftHasExplicitOrder && rightHasExplicitOrder) {
        return 1;
      }
      return left.requestIndex.compareTo(right.requestIndex);
    });

    final commands = commandPlans.map((plan) => plan.command).toList(growable: false);

    final batchValidation = _validateSqlBatch(commands);
    if (batchValidation.isError()) {
      final failure = batchValidation.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final database = params['database'] as String?;
    final authDenied = await _clientTokenGate.enforce(
      request: request,
      clientToken: clientToken,
      sqlStatements: commands.map((SqlCommand command) => command.sql),
      investigationSqlOnDeny: _sqlPreviewForBatch(commands),
      requestDatabase: database,
      deadline: deadline,
      deduplicateEquivalentSql: true,
    );
    if (authDenied != null) {
      return authDenied;
    }

    final optionsJson = params['options'] as Map<String, dynamic>?;
    final options = optionsJson != null
        ? _sqlCommandWireMapper.optionsFromJson(optionsJson)
        : const SqlExecutionOptions();
    final effectiveOptions = SqlExecutionOptions(
      timeoutMs: options.timeoutMs,
      maxRows: options.maxRows < limits.maxRows ? options.maxRows : limits.maxRows,
      transaction: options.transaction,
      maxParallelReadOnlyBatchItems: options.maxParallelReadOnlyBatchItems,
    );

    return _support.runIdempotentExecution(
      request: request,
      idempotencyKey: idempotencyKey,
      idempotencyFingerprint: idempotencyFingerprint ?? '',
      idempotentCachePrefetched: true,
      execute: () async {
        final batchStartedAt = DateTime.now().toUtc();
        final result = await _executeSqlBatchWithBudget(
          agentId,
          commands,
          database: database,
          options: effectiveOptions,
          requestId: request.id?.toString(),
          deadline: deadline,
        );

        if (result.isError()) {
          final failure = result.exceptionOrNull()! as domain.Failure;
          final rpcError = FailureToRpcErrorMapper.map(
            failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          );
          return RpcResponse.error(id: request.id, error: rpcError);
        }

        final commandResults = result.getOrThrow();
        final batchFinishedAt = DateTime.now().toUtc();
        final items =
            commandResults
                .map((SqlCommandResult batchResult) {
                  if (batchResult.index < 0 || batchResult.index >= commandPlans.length) {
                    return batchResult;
                  }
                  final requestIndex = commandPlans[batchResult.index].requestIndex;
                  return SqlCommandResult(
                    index: requestIndex,
                    ok: batchResult.ok,
                    rows: batchResult.rows,
                    rowCount: batchResult.rowCount,
                    affectedRows: batchResult.affectedRows,
                    error: batchResult.error,
                    columnMetadata: batchResult.columnMetadata,
                  );
                })
                .toList(growable: false)
              ..sort((left, right) => left.index.compareTo(right.index));

        final resultData = {
          'execution_id': _uuid.v4(),
          'started_at': _executionTimestampUtcIso(batchStartedAt),
          'finished_at': _executionTimestampUtcIso(batchFinishedAt),
          'items': items.map(_sqlCommandWireMapper.resultToJson).toList(growable: false),
          'total_commands': commands.length,
          'successful_commands': items.where((r) => r.ok).length,
          'failed_commands': items.where((r) => !r.ok).length,
        };

        return RpcResponse.success(
          id: request.id,
          result: resultData,
        );
      },
    );
  }

  Future<Result<List<SqlCommandResult>>> _executeSqlBatchWithBudget(
    String agentId,
    List<SqlCommand> commands, {
    required String? database,
    required SqlExecutionOptions options,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final stageTimeout = _support.effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudgetDuration,
    );
    final timeout = mergeBatchOdbcTimeout(
      stageTimeout: stageTimeout,
      timeoutMs: options.timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': RpcSqlBudgetConstants.batchBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      return await _executeSqlBatch(
        agentId,
        commands,
        database: database,
        options: options,
        timeout: timeout,
        sourceRpcRequestId: requestId,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  String _sqlPreviewForBatch(List<SqlCommand> commands) {
    final joined = commands.map((SqlCommand c) => c.sql).join('\n---\n');
    if (joined.length <= _sqlInvestigationBatchPreviewMaxChars) {
      return joined;
    }
    return '${joined.substring(0, _sqlInvestigationBatchPreviewMaxChars)}\n... [truncated]';
  }

  static String _executionTimestampUtcIso(DateTime timestamp) {
    return timestamp.toUtc().toIso8601String();
  }
}

class BatchCommandExecutionPlan {
  const BatchCommandExecutionPlan({
    required this.command,
    required this.requestIndex,
    required this.executionOrder,
  });

  final SqlCommand command;
  final int requestIndex;
  final int? executionOrder;
}
