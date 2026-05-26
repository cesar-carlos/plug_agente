import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';

/// Resolved paging and visibility for `agent.action.getExecution` output streams.
final class AgentActionGetExecutionOutputOptions {
  const AgentActionGetExecutionOutputOptions({
    required this.paging,
    required this.exposeStdout,
    required this.exposeStderr,
  });

  final AgentActionExecutionOutputPaging paging;
  final bool exposeStdout;
  final bool exposeStderr;
}

int _streamOffsetUtf8(
  Map<String, dynamic> params, {
  required String offsetKey,
  required String cursorKey,
  int? legacyOutputOffset,
}) {
  return jsonNonNegativeInt(params[offsetKey]) ?? jsonNonNegativeInt(params[cursorKey]) ?? legacyOutputOffset ?? 0;
}

bool _clientRequestsOutput(Map<String, dynamic> params) {
  final includeOutput = params['include_output'];
  if (includeOutput is bool) {
    return includeOutput;
  }
  return true;
}

/// Builds paging offsets and per-stream visibility from RPC params and capture policy.
AgentActionGetExecutionOutputOptions resolveAgentActionGetExecutionOutputOptions({
  required Map<String, dynamic> params,
  AgentActionCapturePolicy? capturePolicy,
}) {
  final clientWantsOutput = _clientRequestsOutput(params);
  final policy = capturePolicy ?? const AgentActionCapturePolicy();
  final exposeStdout = clientWantsOutput && policy.captureStdout;
  final exposeStderr = clientWantsOutput && policy.captureStderr;

  return AgentActionGetExecutionOutputOptions(
    paging: AgentActionExecutionOutputPaging(
      stdoutOffsetUtf8: _streamOffsetUtf8(
        params,
        offsetKey: 'stdout_offset',
        cursorKey: 'stdout_cursor',
        legacyOutputOffset: jsonNonNegativeInt(params['output_offset']),
      ),
      stderrOffsetUtf8: _streamOffsetUtf8(
        params,
        offsetKey: 'stderr_offset',
        cursorKey: 'stderr_cursor',
      ),
      maxOutputBytesPerStream: AgentActionRpcConstants.resolveMaxOutputBytesPerStream(
        jsonPositiveInt(params['max_output_bytes']),
      ),
    ),
    exposeStdout: exposeStdout,
    exposeStderr: exposeStderr,
  );
}
