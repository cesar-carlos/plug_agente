import 'package:plug_agente/domain/actions/captured_output_utf8_window.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SliceAgentActionCapturedOutput {
  const SliceAgentActionCapturedOutput(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<CapturedOutputUtf8Window>> call({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) {
    return _repository.sliceCapturedOutput(
      executionId: executionId,
      stream: stream,
      offsetUtf8: offsetUtf8,
      maxBytes: maxBytes,
    );
  }
}
