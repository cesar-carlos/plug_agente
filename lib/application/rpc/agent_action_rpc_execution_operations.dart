import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_get_execution_output_options.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_audit_operations.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_remote_infrastructure.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';

class AgentActionRpcExecutionOperations {
  AgentActionRpcExecutionOperations({
    required AgentActionRpcRemoteInfrastructure infrastructure,
    required AgentActionRpcAuditOperations audit,
    RunAgentActionLocally? runAgentActionLocally,
    RunAgentActionViaRemoteTrigger? runAgentActionViaRemoteTrigger,
    CancelAgentActionExecution? cancelAgentActionExecution,
    GetAgentActionExecution? getAgentActionExecution,
    SliceAgentActionCapturedOutput? sliceAgentActionCapturedOutput,
    GetAgentActionDefinition? getAgentActionDefinition,
  }) : _infrastructure = infrastructure,
       _audit = audit,
       _runAgentActionLocally = runAgentActionLocally,
       _runAgentActionViaRemoteTrigger = runAgentActionViaRemoteTrigger,
       _cancelAgentActionExecution = cancelAgentActionExecution,
       _getAgentActionExecution = getAgentActionExecution,
       _sliceAgentActionCapturedOutput = sliceAgentActionCapturedOutput,
       _getAgentActionDefinition = getAgentActionDefinition;

  final AgentActionRpcRemoteInfrastructure _infrastructure;
  final AgentActionRpcAuditOperations _audit;
  final RunAgentActionLocally? _runAgentActionLocally;
  final RunAgentActionViaRemoteTrigger? _runAgentActionViaRemoteTrigger;
  final CancelAgentActionExecution? _cancelAgentActionExecution;
  final GetAgentActionExecution? _getAgentActionExecution;
  final SliceAgentActionCapturedOutput? _sliceAgentActionCapturedOutput;
  final GetAgentActionDefinition? _getAgentActionDefinition;

  Future<RpcResponse> handleAgentActionRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final runner = _runAgentActionViaRemoteTrigger;
    var actionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (runner == null) {
      response = _infrastructure.support.internalError(
        request,
        'Remote agent action trigger dispatch is not configured on this dispatcher.',
      );
    } else if (_infrastructure.agentActionRpcGateResponse(request) case final RpcResponse gated) {
      actionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      response = gated;
    } else {
      actionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      if (request.isNotification) {
        response = _infrastructure.support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _infrastructure.support.invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _infrastructure.support.invalidParams(request, 'params.action_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final idempotencyKey = (params['idempotency_key'] as String?)?.trim() ?? '';
        final auth = await _infrastructure.authorizeAgentActionClientTokenIfNeeded(
          request: request,
          clientToken: clientToken,
          authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
          requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
          actionIdForAllowlist: actionId,
        );
        tokenPolicyForAudit = auth.policy;
        if (auth.denied != null) {
          response = auth.denied!;
        } else {
          final rateLimited = _infrastructure.tryApplyAgentActionRemoteRateLimit(
            request: request,
            agentId: agentId,
            method: request.method,
            scopeActionId: actionId,
            clientToken: clientToken,
          );
          if (rateLimited != null) {
            response = rateLimited;
          } else {
            final traceId = _infrastructure.resolvedRemoteAgentActionTraceId(request);
            final requestedBy = _infrastructure.resolvedRemoteAgentActionRequestedBy(request);
            String? idempotencyKeyForCache;
            var idempotencyFingerprint = '';
            RpcResponse? idempotentEarly;
            if (idempotencyKey.isNotEmpty &&
                _infrastructure.featureFlags.enableSocketIdempotency &&
                _infrastructure.idempotencyStore != null) {
              idempotencyKeyForCache = idempotencyKey;
              idempotencyFingerprint = await _infrastructure.resolveAgentActionRpcIdempotencyFingerprint(request, params);
              idempotentEarly = await _infrastructure.support.consumeIdempotentCacheIfAny(
                request,
                idempotencyKeyForCache,
                idempotencyFingerprint,
              );
            }
            if (idempotentEarly != null) {
              response = idempotentEarly;
            } else {
              final triggerId = _infrastructure.trimmedAgentActionRpcStringParam(
                request,
                AgentActionRpcConstants.agentActionRpcParamTriggerId,
              );
              response = await _infrastructure.support.runIdempotentExecution(
                request: request,
                idempotencyKey: idempotencyKeyForCache,
                idempotencyFingerprint: idempotencyFingerprint,
                execute: () async {
                  final result = await runner(
                    actionId: actionId,
                    idempotencyKey: idempotencyKey,
                    triggerId: triggerId,
                    requestedBy: requestedBy,
                    traceId: traceId,
                  );
                  return result.fold<Future<RpcResponse>>(
                    (AgentActionExecution execution) async => RpcResponse.success(
                      id: request.id,
                      result: agentActionExecutionToGetExecutionResult(
                        execution,
                        sanitizeForRemoteHub: true,
                      ),
                    ),
                    (Exception failure) async => RpcResponse.error(
                      id: request.id,
                      error: FailureToRpcErrorMapper.map(
                        failure as domain.Failure,
                        instance: request.id?.toString(),
                        useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
                      ),
                    ),
                  );
                },
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _infrastructure.resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _audit.finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
      actionId: actionId.isEmpty ? null : actionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<RpcResponse> handleAgentActionValidateRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final runner = _runAgentActionLocally;
    var actionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (runner == null) {
      response = _infrastructure.support.internalError(request, 'Agent action execution is not configured on this dispatcher.');
    } else if (_infrastructure.agentActionRpcGateResponse(request) case final RpcResponse gated) {
      actionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      response = gated;
    } else {
      actionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      if (request.isNotification) {
        response = _infrastructure.support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _infrastructure.support.invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _infrastructure.support.invalidParams(request, 'params.action_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final idempotencyKey = (params['idempotency_key'] as String?)?.trim() ?? '';
        final auth = await _infrastructure.authorizeAgentActionClientTokenIfNeeded(
          request: request,
          clientToken: clientToken,
          authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionValidateRun,
          requiredAgentActionScope: AgentActionRpcConstants.agentActionsValidateRunScope,
          actionIdForAllowlist: actionId,
        );
        tokenPolicyForAudit = auth.policy;
        if (auth.denied != null) {
          response = auth.denied!;
        } else {
          final rateLimited = _infrastructure.tryApplyAgentActionRemoteRateLimit(
            request: request,
            agentId: agentId,
            method: request.method,
            scopeActionId: actionId,
            clientToken: clientToken,
          );
          if (rateLimited != null) {
            response = rateLimited;
          } else {
            final traceId = _infrastructure.resolvedRemoteAgentActionTraceId(request);
            final requestedBy = _infrastructure.resolvedRemoteAgentActionRequestedBy(request);
            String? idempotencyKeyForCache;
            var idempotencyFingerprint = '';
            RpcResponse? idempotentEarly;
            if (idempotencyKey.isNotEmpty &&
                _infrastructure.featureFlags.enableSocketIdempotency &&
                _infrastructure.idempotencyStore != null) {
              idempotencyKeyForCache = idempotencyKey;
              idempotencyFingerprint = await _infrastructure.resolveAgentActionRpcIdempotencyFingerprint(request, params);
              idempotentEarly = await _infrastructure.support.consumeIdempotentCacheIfAny(
                request,
                idempotencyKeyForCache,
                idempotencyFingerprint,
              );
            }
            if (idempotentEarly != null) {
              response = idempotentEarly;
            } else {
              response = await _infrastructure.support.runIdempotentExecution(
                request: request,
                idempotencyKey: idempotencyKeyForCache,
                idempotencyFingerprint: idempotencyFingerprint,
                execute: () async {
                  final result = await runner.validateRemoteRun(
                    AgentActionExecutionRequest(
                      actionId: actionId,
                      source: AgentActionRequestSource.remoteHub,
                      idempotencyKey: idempotencyKey,
                      requestedBy: requestedBy,
                      traceId: traceId,
                    ),
                  );
                  return result.fold<Future<RpcResponse>>(
                    (AgentActionValidateRunSummary summary) async => RpcResponse.success(
                      id: request.id,
                      result: summary.toRpcResultJson(),
                    ),
                    (Exception failure) async => RpcResponse.error(
                      id: request.id,
                      error: FailureToRpcErrorMapper.map(
                        failure as domain.Failure,
                        instance: request.id?.toString(),
                        useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
                      ),
                    ),
                  );
                },
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _infrastructure.resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _audit.finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
      actionId: actionId.isEmpty ? null : actionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<RpcResponse> handleAgentActionCancel(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final cancel = _cancelAgentActionExecution;
    var executionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (cancel == null) {
      response = _infrastructure.support.internalError(request, 'Agent action cancel is not configured on this dispatcher.');
    } else if (_infrastructure.agentActionRpcGateResponse(request) case final RpcResponse gated) {
      executionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      response = gated;
    } else {
      executionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      if (request.isNotification) {
        response = _infrastructure.support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _infrastructure.support.invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _infrastructure.support.invalidParams(request, 'params.execution_id is required');
      } else {
        final trimmedCredential = clientToken?.trim();
        final needsAgentActionPolicyContext =
            _infrastructure.featureFlags.enableClientTokenAuthorization &&
            trimmedCredential != null &&
            trimmedCredential.isNotEmpty;
        RpcResponse? prefetchFailureResponse;
        var executionActionIdForPolicy = '';
        if (needsAgentActionPolicyContext) {
          final lookup = _getAgentActionExecution;
          if (lookup == null) {
            prefetchFailureResponse = _infrastructure.support.internalError(
              request,
              'Agent action execution lookup is not configured on this dispatcher.',
            );
          } else {
            final prefetchResult = await lookup(executionId);
            prefetchResult.fold(
              (AgentActionExecution execution) => executionActionIdForPolicy = execution.actionId,
              (Exception failure) => prefetchFailureResponse = RpcResponse.error(
                id: request.id,
                error: FailureToRpcErrorMapper.map(
                  failure as domain.Failure,
                  instance: request.id?.toString(),
                  useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
                ),
              ),
            );
          }
        }
        if (prefetchFailureResponse != null) {
          response = prefetchFailureResponse!;
        } else {
          final auth = await _infrastructure.authorizeAgentActionClientTokenIfNeeded(
            request: request,
            clientToken: clientToken,
            authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionCancel,
            requiredAgentActionScope: AgentActionRpcConstants.agentActionsCancelScope,
            actionIdForAllowlist: executionActionIdForPolicy,
          );
          tokenPolicyForAudit = auth.policy;
          if (auth.denied != null) {
            response = auth.denied!;
          } else {
            final rateLimited = _infrastructure.tryApplyAgentActionRemoteRateLimit(
              request: request,
              agentId: agentId,
              method: request.method,
              scopeActionId: executionId,
              clientToken: clientToken,
            );
            if (rateLimited != null) {
              response = rateLimited;
            } else {
              final result = await cancel(executionId);
              response = await result.fold(
                (AgentActionExecution execution) async {
                  final correlated = await _infrastructure.withRpcCorrelationBackfill(execution, request);
                  return RpcResponse.success(
                    id: request.id,
                    result: agentActionCancelToRpcResult(correlated, cancelled: true),
                  );
                },
                (Exception failure) async => RpcResponse.error(
                  id: request.id,
                  error: FailureToRpcErrorMapper.map(
                    failure as domain.Failure,
                    instance: request.id?.toString(),
                    useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
                  ),
                ),
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _infrastructure.resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _audit.finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
      executionId: executionId.isEmpty ? null : executionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<Map<String, dynamic>> agentActionGetExecutionRpcResult({
    required AgentActionExecution execution,
    required Map<String, dynamic> params,
  }) async {
    final outputOptions = await loadGetExecutionOutputOptions(
      params: params,
      execution: execution,
    );
    CapturedOutputUtf8Window? stdoutWindow;
    CapturedOutputUtf8Window? stderrWindow;
    final slice = _sliceAgentActionCapturedOutput;
    if (slice != null) {
      if (execution.stdoutStoredInChunks && outputOptions.exposeStdout) {
        final sliceResult = await slice(
          executionId: execution.id,
          stream: AgentActionCapturedOutputConstants.stdoutStream,
          offsetUtf8: outputOptions.paging.stdoutOffsetUtf8,
          maxBytes: outputOptions.paging.maxOutputBytesPerStream,
        );
        stdoutWindow = sliceResult.getOrNull();
      }
      if (execution.stderrStoredInChunks && outputOptions.exposeStderr) {
        final sliceResult = await slice(
          executionId: execution.id,
          stream: AgentActionCapturedOutputConstants.stderrStream,
          offsetUtf8: outputOptions.paging.stderrOffsetUtf8,
          maxBytes: outputOptions.paging.maxOutputBytesPerStream,
        );
        stderrWindow = sliceResult.getOrNull();
      }
    }

    return agentActionExecutionToGetExecutionResult(
      execution,
      paging: outputOptions.paging,
      exposeStdout: outputOptions.exposeStdout,
      exposeStderr: outputOptions.exposeStderr,
      sanitizeForRemoteHub: true,
      stdoutWindow: stdoutWindow,
      stderrWindow: stderrWindow,
    );
  }

  Future<RpcResponse> handleAgentActionGetExecution(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final getExecution = _getAgentActionExecution;
    var executionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (getExecution == null) {
      response = _infrastructure.support.internalError(request, 'Agent action execution lookup is not configured on this dispatcher.');
    } else if (_infrastructure.agentActionRpcGateResponse(request) case final RpcResponse gated) {
      executionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      response = gated;
    } else {
      executionId = _infrastructure.trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _audit.appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      if (request.isNotification) {
        response = _infrastructure.support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _infrastructure.support.invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _infrastructure.support.invalidParams(request, 'params.execution_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final trimmedCredential = clientToken?.trim();
        final needsAgentActionPolicyContext =
            _infrastructure.featureFlags.enableClientTokenAuthorization &&
            trimmedCredential != null &&
            trimmedCredential.isNotEmpty;
        RpcResponse? prefetchFailureResponse;
        AgentActionExecution? cachedExecution;
        if (needsAgentActionPolicyContext) {
          final prefetchResult = await getExecution(
            executionId,
            hydrateCapturedOutput: false,
          );
          prefetchResult.fold(
            (AgentActionExecution execution) => cachedExecution = execution,
            (Exception failure) => prefetchFailureResponse = RpcResponse.error(
              id: request.id,
              error: FailureToRpcErrorMapper.map(
                failure as domain.Failure,
                instance: request.id?.toString(),
                useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
              ),
            ),
          );
        }
        if (prefetchFailureResponse != null) {
          response = prefetchFailureResponse!;
        } else {
          final auth = await _infrastructure.authorizeAgentActionClientTokenIfNeeded(
            request: request,
            clientToken: clientToken,
            authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionGetExecution,
            requiredAgentActionScope: AgentActionRpcConstants.agentActionsReadExecutionScope,
            actionIdForAllowlist: cachedExecution?.actionId ?? '',
          );
          tokenPolicyForAudit = auth.policy;
          if (auth.denied != null) {
            response = auth.denied!;
          } else {
            final rateLimited = _infrastructure.tryApplyAgentActionRemoteRateLimit(
              request: request,
              agentId: agentId,
              method: request.method,
              scopeActionId: executionId,
              clientToken: clientToken,
            );
            if (rateLimited != null) {
              response = rateLimited;
            } else {
              final cached = cachedExecution;
              if (cached != null) {
                final correlated = await _infrastructure.withRpcCorrelationBackfill(cached, request);
                response = RpcResponse.success(
                  id: request.id,
                  result: await agentActionGetExecutionRpcResult(
                    execution: correlated,
                    params: params,
                  ),
                );
              } else {
                final result = await getExecution(
                  executionId,
                  hydrateCapturedOutput: false,
                );
                response = await result.fold(
                  (AgentActionExecution execution) async {
                    final correlated = await _infrastructure.withRpcCorrelationBackfill(execution, request);
                    return RpcResponse.success(
                      id: request.id,
                      result: await agentActionGetExecutionRpcResult(
                        execution: correlated,
                        params: params,
                      ),
                    );
                  },
                  (Exception failure) async => RpcResponse.error(
                    id: request.id,
                    error: FailureToRpcErrorMapper.map(
                      failure as domain.Failure,
                      instance: request.id?.toString(),
                      useTimeoutByStage: _infrastructure.featureFlags.enableSocketTimeoutByStage,
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    }

    final policyForAudit = await _infrastructure.resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _audit.finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
      executionId: executionId.isEmpty ? null : executionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<AgentActionGetExecutionOutputOptions> loadGetExecutionOutputOptions({
    required Map<String, dynamic> params,
    required AgentActionExecution execution,
  }) async {
    AgentActionCapturePolicy? capturePolicy;
    final getDefinition = _getAgentActionDefinition;
    if (getDefinition != null) {
      final definitionResult = await getDefinition(execution.actionId);
      if (definitionResult.isSuccess()) {
        capturePolicy = definitionResult.getOrThrow().policies.capture;
      }
    }

    return resolveAgentActionGetExecutionOutputOptions(
      params: params,
      capturePolicy: capturePolicy,
    );
  }
}
