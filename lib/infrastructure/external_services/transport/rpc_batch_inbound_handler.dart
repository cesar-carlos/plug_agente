import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_guard_mapping.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_validation_error_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

/// Processes inbound JSON-RPC batch requests after envelope decode.
class RpcBatchInboundHandler {
  RpcBatchInboundHandler({
    required FeatureFlags featureFlags,
    required ProtocolConfig Function() protocolProvider,
    required PayloadLogSummarizer logSummarizer,
    required RpcResponsePreparer responsePreparer,
    required AuthorizationDecisionLogger authorizationDecisionLogger,
    required IRpcRequestDispatcher dispatcher,
    required RpcRequestGuard requestGuard,
    required RpcRequestSchemaValidator schemaValidator,
    required String Function() agentIdProvider,
    required Future<void> Function(
      dynamic responseData, {
      Map<Object?, String> methodsById,
    })
    emitInboundRpcResponse,
    required Future<void> Function(String event, dynamic payload) emitEvent,
    required Future<void> Function(
      dynamic id,
      int code,
      String technicalMessage, {
      String? errorReason,
    })
    sendSchemaValidationError,
    required Future<bool> Function(List<dynamic> data) validateBatchRequestJsonSchemasOrEmit,
    required bool Function(Map<String, dynamic> requestMap) hasNullIdCompatibilityViolation,
    MetricsCollector? metricsCollector,
  }) : _featureFlags = featureFlags,
       _protocolProvider = protocolProvider,
       _logSummarizer = logSummarizer,
       _responsePreparer = responsePreparer,
       _authorizationDecisionLogger = authorizationDecisionLogger,
       _dispatcher = dispatcher,
       _requestGuard = requestGuard,
       _schemaValidator = schemaValidator,
       _agentIdProvider = agentIdProvider,
       _emitInboundRpcResponse = emitInboundRpcResponse,
       _emitEvent = emitEvent,
       _sendSchemaValidationError = sendSchemaValidationError,
       _validateBatchRequestJsonSchemasOrEmit = validateBatchRequestJsonSchemasOrEmit,
       _hasNullIdCompatibilityViolation = hasNullIdCompatibilityViolation,
       _metricsCollector = metricsCollector;

  final FeatureFlags _featureFlags;
  final ProtocolConfig Function() _protocolProvider;
  final PayloadLogSummarizer _logSummarizer;
  final RpcResponsePreparer _responsePreparer;
  final AuthorizationDecisionLogger _authorizationDecisionLogger;
  final IRpcRequestDispatcher _dispatcher;
  final RpcRequestGuard _requestGuard;
  final RpcRequestSchemaValidator _schemaValidator;
  final String Function() _agentIdProvider;
  final Future<void> Function(
    dynamic responseData, {
    Map<Object?, String> methodsById,
  })
  _emitInboundRpcResponse;
  final Future<void> Function(String event, dynamic payload) _emitEvent;
  final Future<void> Function(
    dynamic id,
    int code,
    String technicalMessage, {
    String? errorReason,
  })
  _sendSchemaValidationError;
  final Future<bool> Function(List<dynamic> data) _validateBatchRequestJsonSchemasOrEmit;
  final bool Function(Map<String, dynamic> requestMap) _hasNullIdCompatibilityViolation;
  final MetricsCollector? _metricsCollector;

  /// Validates the batch envelope, dispatches each item independently, then
  /// emits the merged batch response (optionally preserving order based on the
  /// negotiated extension).
  Future<void> handleBatchRequest(List<dynamic> data) async {
    try {
      if (data.isEmpty) {
        const code = RpcErrorCode.invalidRequest;
        final errorResponse = RpcResponse.error(
          id: null,
          error: RpcError(
            code: code,
            message: RpcErrorCode.getMessage(code),
            data: RpcErrorCode.buildErrorData(
              code: code,
              technicalMessage: RpcInboundConstants.batchRequestEmptyDetail,
              extra: {'detail': RpcInboundConstants.batchRequestEmptyDetail},
            ),
          ),
        );
        await _emitInboundRpcResponse(errorResponse);
        return;
      }

      if (_exceedsPayloadLimit(data)) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidPayload,
          RpcInboundConstants.batchRequestExceedsPayloadLimitTechnicalMessage,
        );
        return;
      }

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateBatch(
          data,
          limits: _protocolProvider().effectiveLimits,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              null,
              rpcInboundValidationFailureCode(failure),
              failure.message,
            );
            return;
          }
        }
        if (!await _validateBatchRequestJsonSchemasOrEmit(data)) {
          return;
        }
      }

      for (final item in data) {
        if (item is! Map<String, dynamic>) {
          await _sendSchemaValidationError(
            null,
            RpcErrorCode.invalidRequest,
            RpcInboundConstants.eachBatchElementMustBeJsonObjectTechnicalMessage,
          );
          return;
        }
        if (!_responsePreparer.verifyIncomingSignature(item)) {
          await _sendSchemaValidationError(
            item['id'],
            RpcErrorCode.authenticationFailed,
            RpcInboundConstants.invalidPayloadSignatureTechnicalMessage,
            errorReason: RpcErrorCode.reasonInvalidSignature,
          );
          return;
        }
      }

      final requests = data.map((e) => RpcRequest.fromJson(e as Map<String, dynamic>)).toList();

      for (final item in data.whereType<Map<String, dynamic>>()) {
        if (_hasNullIdCompatibilityViolation(item)) {
          await _sendSchemaValidationError(
            null,
            RpcErrorCode.invalidRequest,
            RpcInboundConstants.nullIdNotificationsCompatibilityTechnicalMessage,
          );
          return;
        }
      }

      if (_featureFlags.enableSocketDeliveryGuarantees) {
        await _emitBatchRequestAck(requests);
      }

      if (_featureFlags.enableSocketBatchStrictValidation) {
        final batch = RpcBatchRequest(requests);
        final validation = batch.validateStrict(
          maxSize: _protocolProvider().effectiveLimits.maxBatchSize,
        );
        switch (validation) {
          case RpcBatchDuplicateIds(:final duplicateIds):
            await _emitInboundRpcResponse(
              RpcResponse.error(
                id: null,
                error: RpcError(
                  code: RpcErrorCode.invalidRequest,
                  message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                  data: RpcErrorCode.buildErrorData(
                    code: RpcErrorCode.invalidRequest,
                    technicalMessage: '${RpcBatchConstants.duplicateRequestIdsTechnicalMessagePrefix}$duplicateIds',
                    reason: RpcBatchConstants.duplicateRequestIdsReason,
                    extra: {'duplicate_ids': duplicateIds},
                  ),
                ),
              ),
            );
            return;
          case RpcBatchExceedsLimit(:final size, :final limit):
            await _emitInboundRpcResponse(
              RpcResponse.error(
                id: null,
                error: RpcError(
                  code: RpcErrorCode.invalidRequest,
                  message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                  data: RpcErrorCode.buildErrorData(
                    code: RpcErrorCode.invalidRequest,
                    technicalMessage: '${RpcBatchConstants.exceedsLimitTechnicalMessagePrefix}$size > $limit',
                    reason: RpcBatchConstants.exceedsLimitReason,
                    extra: {'size': size, 'limit': limit},
                  ),
                ),
              ),
            );
            return;
          case RpcBatchValid():
            break;
        }
      }

      final readOnlyAgentActionCount = requests
          .where((request) => _isAgentActionBatchReadMethod(request.method))
          .length;
      final maxReadPerBatch = AgentActionPolicyDefaults.maxAgentActionReadRpcMethodsPerBatch;
      if (readOnlyAgentActionCount > maxReadPerBatch) {
        _metricsCollector?.recordRpcAgentActionBatchReadLimitRejected();
        await _emitInboundRpcResponse(
          RpcResponse.error(
            id: null,
            error: RpcError(
              code: RpcErrorCode.invalidRequest,
              message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
              data: RpcErrorCode.buildErrorData(
                code: RpcErrorCode.invalidRequest,
                technicalMessage:
                    '${AgentActionRpcConstants.jsonRpcBatchAgentActionReadLimitTechnicalMessagePrefix}'
                    '$readOnlyAgentActionCount > $maxReadPerBatch',
                reason: AgentActionRpcConstants.jsonRpcBatchAgentActionReadLimitErrorReason,
                extra: <String, Object?>{
                  'read_method_count': readOnlyAgentActionCount,
                  'limit': maxReadPerBatch,
                },
              ),
            ),
          ),
        );
        return;
      }

      final responses = <({int index, RpcResponse response})>[];
      final responseMethodsById = <Object?, String>{};

      for (var index = 0; index < requests.length; index++) {
        final request = requests[index];
        if (_isAgentActionBatchRejectedMethod(request.method)) {
          final errorResponse = _responsePreparer.buildErrorResponse(
            id: request.id,
            code: RpcErrorCode.invalidRequest,
            technicalMessage:
                '${AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedTechnicalMessagePrefix}'
                '${request.method}'
                '${AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedTechnicalMessageSuffix}',
            errorReason: AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedErrorReason,
          );
          if (!request.isNotification) {
            responses.add((index: index, response: errorResponse));
            responseMethodsById[request.id] = request.method;
          }
          continue;
        }

        final guardResult = _requestGuard.evaluate(request);
        if (guardResult != RpcRequestGuardResult.allow) {
          final errorResponse = _responsePreparer.buildErrorResponse(
            id: request.id,
            code: rpcInboundGuardResultToCode(guardResult),
            technicalMessage: rpcInboundGuardResultToTechnicalMessage(guardResult),
            errorReason: rpcInboundGuardResultToReason(guardResult),
          );
          if (!request.isNotification) {
            responses.add((index: index, response: errorResponse));
            responseMethodsById[request.id] = request.method;
          }
          continue;
        }

        final clientToken = _extractClientTokenFromRpcParams(request.params);
        final response = await _dispatcher.dispatch(
          request,
          _agentIdProvider(),
          clientToken: clientToken,
          limits: _protocolProvider().effectiveLimits,
          negotiatedExtensions: _protocolProvider().negotiatedExtensions,
        );
        final tracedResponse = _responsePreparer.attachRequestTrace(request, response);
        _authorizationDecisionLogger.log(
          request: request,
          response: tracedResponse,
          clientToken: clientToken,
        );
        if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
          continue;
        }
        responses.add((index: index, response: tracedResponse));
        responseMethodsById[request.id] = request.method;
      }

      if (responses.isEmpty) {
        return;
      }

      final orderedResponses = _supportsOrderedBatchResponses()
          ? (responses.toList()..sort((left, right) => left.index.compareTo(right.index)))
                .map((entry) => entry.response)
                .toList()
          : responses.map((entry) => entry.response).toList();
      await _emitInboundRpcResponse(
        orderedResponses,
        methodsById: responseMethodsById,
      );
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC batch request',
        error,
        stackTrace,
      );
      final errorResponse = RpcResponse.error(
        id: null,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.internalError,
            technicalMessage: RpcInboundConstants.unhandledBatchProcessingTechnicalMessage,
            extra: {'failure_code': RpcInboundConstants.unhandledBatchExceptionFailureCode},
          ),
        ),
      );
      try {
        await _emitInboundRpcResponse(errorResponse);
      } on Object catch (emitError, emitStack) {
        AppLogger.error(
          'Failed to emit batch error response',
          emitError,
          emitStack,
        );
      }
    }
  }

  bool _isAgentActionBatchRejectedMethod(String method) {
    return AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethods.contains(method);
  }

  bool _isAgentActionBatchReadMethod(String method) {
    return method == AgentActionRpcConstants.agentActionGetExecutionRpcMethodName ||
        method == AgentActionRpcConstants.agentActionValidateRunRpcMethodName;
  }

  Future<void> _emitBatchRequestAck(List<RpcRequest> requests) async {
    if (requests.isEmpty) return;
    final ids = requests.where((r) => r.id != null).map((r) => r.id.toString()).toList();
    if (ids.isEmpty) return;
    final ackPayload = {
      'request_ids': ids,
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEvent('rpc:batch_ack', ackPayload);
  }

  bool _exceedsPayloadLimit(dynamic payload) {
    final limit = _protocolProvider().effectiveLimits.maxDecodedPayloadBytes;
    return _logSummarizer.exceedsByteBudget(payload, limit);
  }

  bool _supportsOrderedBatchResponses() {
    final extensionValue = _protocolProvider().negotiatedExtensions['orderedBatchResponses'];
    if (extensionValue is bool) return extensionValue;
    return true;
  }

  String? _extractClientTokenFromRpcParams(dynamic params) {
    if (params is! Map<String, dynamic>) return null;
    final raw = params['client_token'] as String? ?? params['auth'] as String? ?? params['clientToken'] as String?;
    return raw != null && raw.trim().isNotEmpty ? raw.trim() : null;
  }
}
