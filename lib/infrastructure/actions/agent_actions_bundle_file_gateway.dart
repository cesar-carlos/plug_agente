import 'dart:io';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_actions_bundle_file_gateway.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionsBundleFileGateway implements IAgentActionsBundleFileGateway {
  const AgentActionsBundleFileGateway();

  @override
  Future<Result<void>> writeText(String filePath, String payload) async {
    try {
      await File(filePath).writeAsString(payload);
      return const Success(unit);
    } on IOException catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to write agent actions bundle file',
          cause: error,
          context: {'operation': 'writeText', 'filePath': filePath},
        ),
      );
    }
  }

  @override
  Future<Result<String>> readText(String filePath) async {
    try {
      final payload = await File(filePath).readAsString();
      return Success(payload);
    } on IOException catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to read agent actions bundle file',
          cause: error,
          context: {'operation': 'readText', 'filePath': filePath},
        ),
      );
    }
  }
}
