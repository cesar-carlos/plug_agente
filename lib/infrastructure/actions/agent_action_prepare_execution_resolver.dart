import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

Future<Result<AgentActionPreparedExecution>> resolvePreparedExecution({
  required AgentActionAdapter adapter,
  required AgentActionDefinition definition,
  required AgentActionExecutionRequest request,
}) {
  final cached = request.cachedPreparedExecution;
  if (cached != null) {
    return Future<Result<AgentActionPreparedExecution>>.value(Success(cached));
  }

  return adapter.prepareExecution(
    definition: definition,
    request: request,
  );
}
