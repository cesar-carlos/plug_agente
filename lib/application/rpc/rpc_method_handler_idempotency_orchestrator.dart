import 'dart:async';

import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_support.dart';
import 'package:plug_agente/application/rpc/agent_metadata_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/rpc_idempotency_coordinator.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:result_dart/result_dart.dart';

class RpcMethodHandlerIdempotencyOrchestrator {
  RpcMethodHandlerIdempotencyOrchestrator({
    required AuthorizeSqlOperation authorizeSqlOperation,
    required FeatureFlags featureFlags,
    IIdempotencyStore? idempotencyStore,
    RpcIdempotencyCoordinator? idempotencyCoordinator,
    void Function()? onIdempotencyFingerprintMismatch,
    AgentActionRetentionSettings? agentActionRetentionSettings,
    Duration authorizationStageBudget = const Duration(seconds: 3),
  }) : _authorizeSqlOperation = authorizeSqlOperation,
       _featureFlags = featureFlags,
       _idempotencyStore = idempotencyStore,
       _idempotencyCoordinator = idempotencyCoordinator ?? RpcIdempotencyCoordinator(),
       _onIdempotencyFingerprintMismatch = onIdempotencyFingerprintMismatch,
       _agentActionRetentionSettings = agentActionRetentionSettings,
       _authorizationStageBudgetDuration = authorizationStageBudget;

  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final IIdempotencyStore? _idempotencyStore;
  final RpcIdempotencyCoordinator _idempotencyCoordinator;
  final void Function()? _onIdempotencyFingerprintMismatch;
  final AgentActionRetentionSettings? _agentActionRetentionSettings;
  final Duration _authorizationStageBudgetDuration;

  SqlRpcMethodHandlerSupport buildSqlSupport() {
    return SqlRpcMethodHandlerSupport(
      invalidParams: invalidParams,
      methodNotFound: methodNotFound,
      executionNotFound: executionNotFound,
      consumeIdempotentCacheIfAny: consumeIdempotentCacheIfAny,
      storeIdempotentSuccessIfApplicable: storeIdempotentSuccessIfApplicable,
      runIdempotentExecution: runIdempotentExecution,
      buildMissingClientTokenFailure: buildMissingClientTokenFailure,
      authorizeWithBudget: authorizeWithBudget,
      effectiveStageTimeout: effectiveStageTimeout,
    );
  }

  AgentActionRpcMethodHandlerSupport buildAgentActionSupport() {
    return AgentActionRpcMethodHandlerSupport(
      invalidParams: invalidParams,
      internalError: internalError,
      consumeIdempotentCacheIfAny: consumeIdempotentCacheIfAny,
      storeIdempotentSuccessIfApplicable: storeIdempotentSuccessIfApplicable,
      runIdempotentExecution: runIdempotentExecution,
    );
  }

  AgentMetadataRpcMethodHandlerSupport buildMetadataSupport() {
    return AgentMetadataRpcMethodHandlerSupport(
      invalidParams: invalidParams,
      internalError: internalError,
      buildMissingClientTokenFailure: buildMissingClientTokenFailure,
      authorizeWithBudget: authorizeWithBudget,
    );
  }

  String namespacedRpcIdempotencyStoreKey(
    RpcRequest request,
    String idempotencyKey,
  ) => '${request.method}:$idempotencyKey';

  Duration rpcIdempotencyEntryTtl(RpcRequest request) {
    switch (request.method) {
      case AgentActionRpcConstants.agentActionRunRpcMethodName:
        return _agentActionRetentionSettings?.agentActionRpcIdempotencyTtl ??
            ConnectionConstants.agentActionRpcIdempotencyEntryTtl;
      default:
        return ConnectionConstants.rpcIdempotencyEntryTtl;
    }
  }

  Future<Result<void>> authorizeWithBudget({
    required String token,
    required String sql,
    required String? requestDatabase,
    required String? requestId,
    required String method,
    required DateTime? deadline,
  }) async {
    final timeout = effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _authorizationStageBudgetDuration,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': RpcSqlBudgetConstants.authorizationBudgetExhaustedReason,
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization budget exhausted before validation',
          context: context,
        ),
      );
    }

    try {
      if (timeout == null) {
        return _authorizeSqlOperation(
          token: token,
          sql: sql,
          requestDatabase: requestDatabase,
          requestId: requestId,
          method: method,
        );
      }
      return await _authorizeSqlOperation(
        token: token,
        sql: sql,
        requestDatabase: requestDatabase,
        requestId: requestId,
        method: method,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': RpcSqlBudgetConstants.authorizationTimeoutReason,
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization stage timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Duration? effectiveStageTimeout({
    required DateTime? deadline,
    required Duration stageBudget,
  }) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining < stageBudget ? remaining : stageBudget;
  }

  RpcResponse executionNotFound(RpcRequest request) {
    const code = RpcErrorCode.executionNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage:
              'No in-flight execution found to cancel. '
              'Execution may have completed or never started.',
          correlationId: request.id?.toString(),
          extra: {'method': 'sql.cancel'},
        ),
      ),
    );
  }

  RpcResponse methodNotFound(RpcRequest request) {
    const code = RpcErrorCode.methodNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'RPC method not found: ${request.method}',
          correlationId: request.id?.toString(),
          extra: {
            'method': request.method,
          },
        ),
      ),
    );
  }

  RpcResponse invalidParams(
    RpcRequest request,
    String detail, {
    String? rpcReason,
    Map<String, dynamic> extraFields = const <String, dynamic>{},
  }) {
    const code = RpcErrorCode.invalidParams;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          reason: rpcReason ?? RpcErrorCode.getReason(code),
          extra: <String, dynamic>{
            'detail': detail,
            'method': request.method,
            ...extraFields,
          },
        ),
      ),
    );
  }

  RpcResponse internalError(RpcRequest request, String detail) {
    const code = RpcErrorCode.internalError;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          extra: {'detail': detail},
        ),
      ),
    );
  }

  Future<RpcResponse> runIdempotentExecution({
    required RpcRequest request,
    required String? idempotencyKey,
    required String idempotencyFingerprint,
    required Future<RpcResponse> Function() execute,
    // Prefetch remains a caller fast-path; the lock always re-checks cache.
    bool idempotentCachePrefetched = false,
  }) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty ||
        _idempotencyStore == null) {
      return execute();
    }

    final namespacedKey = namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    final response = await _idempotencyCoordinator.runExclusive(
      namespacedKey: namespacedKey,
      action: () async {
        // Always re-check under the lock so staggered retries reuse a response
        // written by the leader even when the outer path already prefetched.
        final cached = await consumeIdempotentCacheIfAny(
          request,
          idempotencyKey,
          idempotencyFingerprint,
        );
        if (cached != null) {
          return cached;
        }
        final executed = await execute();
        final sanitized = RpcWireMap.sanitizeRpcResponse(executed);
        await storeIdempotentSuccessIfApplicable(
          request: request,
          idempotencyKey: idempotencyKey,
          idempotencyFingerprint: idempotencyFingerprint,
          response: sanitized,
        );
        return sanitized;
      },
    );
    return _idempotencyCoordinator.remapResponseId(response, request.id);
  }

  Future<RpcResponse?> consumeIdempotentCacheIfAny(
    RpcRequest request,
    String? idempotencyKey,
    String idempotencyFingerprint,
  ) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      return null;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return null;
    }
    final namespacedKey = namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    final cachedRecord = await store.getRecord(namespacedKey);
    if (cachedRecord != null &&
        cachedRecord.requestFingerprint != null &&
        cachedRecord.requestFingerprint != idempotencyFingerprint) {
      _onIdempotencyFingerprintMismatch?.call();
      if (request.method.startsWith('agent.action.')) {
        return invalidParams(
          request,
          'idempotency_key was already used with a different request payload',
          rpcReason: AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason,
          extraFields: <String, dynamic>{
            'category': RpcErrorCode.categoryAction,
            'idempotency_key': idempotencyKey,
          },
        );
      }
      return invalidParams(
        request,
        'idempotency_key was already used with a different request payload',
      );
    }
    final cached = cachedRecord?.response;
    if (cached != null) {
      return RpcResponse(
        jsonrpc: cached.jsonrpc,
        id: request.id,
        result: cached.result,
        error: cached.error,
        apiVersion: cached.apiVersion,
        meta: cached.meta,
      );
    }
    return null;
  }

  Future<void> storeIdempotentSuccessIfApplicable({
    required RpcRequest request,
    required String? idempotencyKey,
    required String idempotencyFingerprint,
    required RpcResponse response,
  }) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty ||
        !response.isSuccess) {
      return;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return;
    }
    final namespacedKey = namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    await store.set(
      namespacedKey,
      response,
      rpcIdempotencyEntryTtl(request),
      requestFingerprint: idempotencyFingerprint,
    );
  }

  domain.ConfigurationFailure buildMissingClientTokenFailure() {
    return domain.ConfigurationFailure.withContext(
      message: 'Client token is required for authorized SQL operations',
      context: {
        'authentication': true,
        'reason': RpcClientTokenConstants.missingClientTokenReason,
      },
    );
  }
}
