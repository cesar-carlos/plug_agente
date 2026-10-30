import 'dart:convert';

import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/application/actions/action_io_remote_access.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/action_io_request_parser.dart';
import 'package:plug_agente/application/rpc/action_io_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_action_io_rpc_contract.dart';

final class ActionIoRpcHandler implements RpcMethodHandler {
  ActionIoRpcHandler(
    this.method, {
    required IActionIoRpcContract contract,
    required bool Function() enabled,
    this.validateRun,
    this.run,
    ActionIoRemoteAccess? access,
    ActionIoRemoteAccess Function()? accessProvider,
  }) : assert(
         access != null || accessProvider != null || validateRun != null || run != null,
         'An I/O operation provider is required.',
       ),
       _access = accessProvider ?? (() => access!),
       _contract = contract,
       _enabled = enabled;

  static const methods = {
    'agent.action.sendInput',
    'agent.action.closeInput',
    'agent.action.getInputStatus',
    'agent.action.readIo',
    'agent.action.findExecution',
  };
  @override
  final String method;
  final ActionIoRemoteAccess Function() _access;
  final IActionIoRpcContract _contract;
  final bool Function() _enabled;
  final Future<Map<String, dynamic>> Function(RpcRequest, RpcDispatchContext)? validateRun;
  final Future<Map<String, dynamic>> Function(RpcRequest, RpcDispatchContext)? run;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    try {
      final call = context.actionIo;
      if (!_enabled() || !ActionIoCapability.negotiated(context.negotiatedExtensions) || call == null) {
        throw _unavailable('CAPABILITY_UNAVAILABLE');
      }
      if (request.method != method ||
          (!methods.contains(method) &&
              method != 'agent.action.validateRun' &&
              method != 'agent.action.run' &&
              method != 'agent.action.getExecution' &&
              method != 'agent.action.cancel') ||
          request.isNotification) {
        throw _invalid('ACTION_IO_INVALID_REQUEST');
      }
      if (call.connectionId.isEmpty || call.isCancelled() || !DateTime.now().isBefore(call.deadline)) {
        throw _unavailable('ACTION_IO_REQUEST_EXPIRED');
      }
      _contract.validateParams(method, request.params).getOrThrow();
      final params = request.params as Map<String, dynamic>;
      if (call.isBatch &&
          (method == 'agent.action.run' ||
              method == 'agent.action.cancel' ||
              method == 'agent.action.sendInput' ||
              method == 'agent.action.closeInput' ||
              (method == 'agent.action.readIo' && _integer(params, 'wait_ms') > 0))) {
        throw _invalid('ACTION_IO_BATCH_FORBIDDEN');
      }
      final credential = context.clientToken;
      if (credential == null ||
          credential.trim().isEmpty ||
          ['client_token', 'clientToken', 'auth'].any((key) => params[key] != null && params[key] != credential)) {
        throw ActionAuthorizationFailure.withContext(
          message: 'A current local credential is required.',
          code: 'ACTION_IO_UNAUTHORIZED',
          context: {'retryable': false},
        );
      }
      ActionIoRemoteAccess getAccess() => _access();
      bool isRequestActive() => !call.isCancelled() && DateTime.now().isBefore(call.deadline);
      final executionId = params['execution_id'] as String? ?? '';
      late final Map<String, dynamic> result;
      switch (method) {
        case 'agent.action.run':
          result = await run!(request, context);
        case 'agent.action.cancel':
          final snapshot = (await getAccess().cancel(
            executionId: executionId,
            agentId: context.agentId,
            credential: credential,
            isRequestActive: isRequestActive,
          )).getOrThrow();
          final execution = ActionIoExecutionProjection.fromSnapshot(snapshot).getOrThrow();
          result = {
            ...agentActionCancelToRpcResult(execution, cancelled: execution.cancelled),
            'execution': ActionIoRpcMapper.execution(snapshot),
          };
        case 'agent.action.getExecution':
          final snapshot = (await getAccess().execution(
            executionId: executionId,
            agentId: context.agentId,
            credential: credential,
          )).getOrThrow();
          result = ActionIoRpcMapper.execution(snapshot);
        case 'agent.action.validateRun':
          result = await validateRun!(request, context);
        case 'agent.action.sendInput':
        case 'agent.action.closeInput':
          final close = method == 'agent.action.closeInput';
          final bytes = close ? <int>[] : ActionIoRequestParser.block(params['data_base64']).getOrThrow();
          result = ActionIoRpcMapper.receipt(
            (await getAccess().send(
              executionId: executionId,
              agentId: context.agentId,
              credential: credential,
              messageId: params['message_id'] as String,
              sequence: _integer(params, 'sequence'),
              bytes: bytes,
              close: close,
              isRequestActive: isRequestActive,
            )).getOrThrow(),
          );
        case 'agent.action.getInputStatus':
          result = ActionIoRpcMapper.receipt(
            (await getAccess().inputStatus(
              executionId: executionId,
              agentId: context.agentId,
              credential: credential,
              messageId: params['message_id'] as String,
            )).getOrThrow(),
          );
        case 'agent.action.readIo':
          result = ActionIoRpcMapper.page(
            executionId,
            (await getAccess().read(
              executionId: executionId,
              agentId: context.agentId,
              credential: credential,
              connectionId: call.connectionId,
              afterSequence: _integer(params, 'after_sequence'),
              maxBytes: _integer(params, 'max_bytes'),
              wait: Duration(milliseconds: _integer(params, 'wait_ms')),
              deadline: call.deadline,
              isCancelled: call.isCancelled,
              onReadWait: call.onReadWait,
            )).getOrThrow(),
          );
        case 'agent.action.findExecution':
          final found = (await getAccess().find(
            agentId: context.agentId,
            credential: credential,
            actionId: params['action_id'] as String,
            idempotencyKey: params['idempotency_key'] as String,
          )).getOrThrow();
          result = {
            'found': found.session != null,
            'execution_id': found.session?.executionId,
            if (found.session == null) 'reason': 'not_found_in_retention_window',
          };
        default:
          throw _invalid('ACTION_IO_INVALID_REQUEST');
      }
      _contract.validateResult(method, result).getOrThrow();
      final response = RpcResponse.success(id: request.id, result: result);
      final size = utf8.encode(jsonEncode(response.toJson())).length;
      if (size > ActionIoLimits.jsonBytes ||
          size > context.limits.maxDecodedPayloadBytes ||
          size > context.limits.maxCompressedPayloadBytes) {
        throw _unavailable('ACTION_IO_PAGE_UNTRANSPORTABLE');
      }
      return response;
    } on domain.Failure catch (failure) {
      return RpcResponse.error(
        id: request.id,
        error: FailureToRpcErrorMapper.map(failure, instance: request.id?.toString()),
      );
    } on Object {
      return RpcResponse.error(
        id: request.id,
        error: FailureToRpcErrorMapper.map(_unavailable('ACTION_IO_UNAVAILABLE'), instance: request.id?.toString()),
      );
    }
  }

  int _integer(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value is! int) throw _invalid('ACTION_IO_INVALID_INPUT');
    return value;
  }

  ActionValidationFailure _invalid(String code) =>
      ActionValidationFailure.withContext(message: 'Invalid I/O request.', code: code, context: {'retryable': false});
  ActionRuntimeFailure _unavailable(String code) => ActionRuntimeFailure.withContext(
    message: 'The I/O operation is unavailable.',
    code: code,
    context: {'retryable': false},
  );
}
