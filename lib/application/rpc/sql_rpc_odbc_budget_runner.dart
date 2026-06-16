import 'dart:async';

import 'package:plug_agente/application/rpc/sql_execute_materialized_result_policy.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class SqlRpcOdbcBudgetRunner {
  const SqlRpcOdbcBudgetRunner({
    required IDatabaseGateway databaseGateway,
    required SqlRpcMethodHandlerSupport support,
    required Duration queryStageBudget,
    required Duration batchExecutionStageBudget,
    SqlExecuteMaterializedResultPolicy materializedPolicy = const SqlExecuteMaterializedResultPolicy(),
  }) : _databaseGateway = databaseGateway,
       _support = support,
       _queryStageBudget = queryStageBudget,
       _batchExecutionStageBudget = batchExecutionStageBudget,
       _materializedPolicy = materializedPolicy;

  final IDatabaseGateway _databaseGateway;
  final SqlRpcMethodHandlerSupport _support;
  final Duration _queryStageBudget;
  final Duration _batchExecutionStageBudget;
  final SqlExecuteMaterializedResultPolicy _materializedPolicy;

  Future<Result<QueryResponse>> executeQuery(
    QueryRequest queryRequest, {
    required String? database,
    required String? requestId,
    required DateTime? deadline,
    required int timeoutMs,
    int? effectiveMaxRows,
    TransportLimits? transportLimits,
    Map<String, dynamic>? negotiatedExtensions,
  }) async {
    if (effectiveMaxRows != null && transportLimits != null && negotiatedExtensions != null) {
      final guard = _materializedPolicy.rejectIfMaterializedPathUnsafe(
        effectiveMaxRows: effectiveMaxRows,
        limits: transportLimits,
        negotiatedExtensions: negotiatedExtensions,
        requestId: requestId,
      );
      if (guard.isError()) {
        return Failure(guard.exceptionOrNull()!);
      }
    }

    final timeout = mergeOdbcTimeout(
      stageTimeout: _support.effectiveStageTimeout(
        deadline: deadline,
        stageBudget: _queryStageBudget,
      ),
      timeoutMs: timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': RpcSqlBudgetConstants.queryBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      final Result<QueryResponse> result;
      if (timeout == null) {
        if (database == null || database.isEmpty) {
          result = await _databaseGateway.executeQuery(queryRequest);
        } else {
          result = await _databaseGateway.executeQuery(
            queryRequest,
            database: database,
          );
        }
      } else {
        result = await _databaseGateway.executeQuery(
          queryRequest,
          timeout: timeout,
          database: database,
        );
      }
      return result;
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Future<Result<int>> executeBulkInsert(
    BulkInsertRequest request, {
    required String? database,
    required int timeoutMs,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final stageTimeout = _support.effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudget,
    );
    final timeout = mergeBatchOdbcTimeout(
      stageTimeout: stageTimeout,
      timeoutMs: timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'bulk_insert',
        'reason': RpcSqlBudgetConstants.bulkInsertBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Bulk insert budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      return await _databaseGateway.executeBulkInsert(
        request,
        database: database,
        timeout: timeout,
        sourceRpcRequestId: requestId,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'bulk_insert',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Bulk insert execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }
}
