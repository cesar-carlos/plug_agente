import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';

/// Handles `sql.cancel` RPC requests.
class SqlCancelHandler {
  SqlCancelHandler({
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    required SqlStreamingCoordinator sqlStreamingCoordinator,
    required IStreamingDatabaseGateway? streamingGateway,
    ISqlInFlightExecutionAbortPort? inFlightAbortPort,
  }) : _featureFlags = featureFlags,
       _support = support,
       _sqlStreamingCoordinator = sqlStreamingCoordinator,
       _streamingGateway = streamingGateway,
       _inFlightAbortPort = inFlightAbortPort;

  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final SqlStreamingCoordinator _sqlStreamingCoordinator;
  final IStreamingDatabaseGateway? _streamingGateway;
  final ISqlInFlightExecutionAbortPort? _inFlightAbortPort;

  Future<RpcResponse> handleSqlCancel(RpcRequest request) async {
    if (!_featureFlags.enableSocketCancelMethod) {
      return _support.methodNotFound(request);
    }

    if (request.params != null && request.params is! Map<String, dynamic>) {
      return _support.invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>? ?? {};
    final executionId = params['execution_id'] as String?;
    final requestId = params['request_id'] as String?;

    if ((executionId == null || executionId.isEmpty) && (requestId == null || requestId.isEmpty)) {
      return _support.invalidParams(
        request,
        'At least one of execution_id or request_id is required',
      );
    }

    final activeExecution = _sqlStreamingCoordinator.find(
      executionId: executionId,
      requestId: requestId,
    );
    if (activeExecution != null) {
      final gateway = _streamingGateway;
      if (gateway == null) {
        return _support.executionNotFound(request);
      }

      if (_featureFlags.enableClientTokenAuthorization) {
        final cancelToken =
            (params['client_token'] as String? ?? params['auth'] as String? ?? params['clientToken'] as String?)
                ?.trim();
        final ownerToken = activeExecution.ownerClientToken;
        if (ownerToken != null && ownerToken.isNotEmpty) {
          if (cancelToken == null || cancelToken.isEmpty || cancelToken != ownerToken) {
            final rpcError = FailureToRpcErrorMapper.map(
              domain.ValidationFailure.withContext(
                message: 'sql.cancel: clientToken does not match the token that started the stream.',
                context: {
                  'reason': 'cancel_token_mismatch',
                  'execution_id': executionId,
                },
              ),
              instance: request.id?.toString(),
              useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
            );
            return RpcResponse.error(id: request.id, error: rpcError);
          }
        }
      }

      final cancelResult = await _sqlStreamingCoordinator.cancel(
        execution: activeExecution,
      );

      return cancelResult.fold(
        (_) => _cancelSuccessResponse(
          request: request,
          executionId: executionId,
          requestId: requestId,
        ),
        (failure) {
          final rpcError = FailureToRpcErrorMapper.map(
            failure as domain.Failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          );
          return RpcResponse.error(id: request.id, error: rpcError);
        },
      );
    }

    final abortTargetId = _resolveInFlightAbortTargetId(
      executionId: executionId,
      requestId: requestId,
    );
    if (abortTargetId != null) {
      final abortPort = _inFlightAbortPort;
      if (abortPort != null) {
        final abortResult = await abortPort.abortInFlightExecution(abortTargetId);
        return abortResult.fold(
          (aborted) {
            if (!aborted) {
              return _support.executionNotFound(request);
            }
            return _cancelSuccessResponse(
              request: request,
              executionId: executionId,
              requestId: requestId,
              viaInFlightAbort: true,
            );
          },
          (failure) {
            final rpcError = FailureToRpcErrorMapper.map(
              failure as domain.Failure,
              instance: request.id?.toString(),
              useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
            );
            return RpcResponse.error(id: request.id, error: rpcError);
          },
        );
      }
    }

    return _support.executionNotFound(request);
  }

  String? _resolveInFlightAbortTargetId({
    required String? executionId,
    required String? requestId,
  }) {
    final normalizedRequestId = requestId?.trim();
    if (normalizedRequestId != null && normalizedRequestId.isNotEmpty) {
      return normalizedRequestId;
    }
    final normalizedExecutionId = executionId?.trim();
    if (normalizedExecutionId != null && normalizedExecutionId.isNotEmpty) {
      return normalizedExecutionId;
    }
    return null;
  }

  RpcResponse _cancelSuccessResponse({
    required RpcRequest request,
    required String? executionId,
    required String? requestId,
    bool viaInFlightAbort = false,
  }) {
    final resultData = <String, dynamic>{
      'cancelled': true,
      if (viaInFlightAbort) 'via_in_flight_abort': true,
      ...?(executionId != null ? {'execution_id': executionId} : null),
      ...?(requestId != null ? {'request_id': requestId} : null),
    };
    return RpcResponse.success(id: request.id, result: resultData);
  }
}
