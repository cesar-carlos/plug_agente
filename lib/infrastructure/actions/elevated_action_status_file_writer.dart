import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Writes terminal elevated helper status JSON when the app must preempt the helper.
class ElevatedActionStatusFileWriter {
  ElevatedActionStatusFileWriter({
    required GlobalStorageContext storageContext,
    DateTime Function()? now,
  }) : _storageContext = storageContext,
       _now = now ?? DateTime.now;

  final GlobalStorageContext _storageContext;
  final DateTime Function() _now;

  Future<Result<void>> writeTerminalStatusIfAbsent({
    required String executionId,
    required AgentActionExecutionStatus status,
    required String failureCode,
    required String failureMessage,
  }) async {
    final trimmedId = executionId.trim();
    if (await _hasTerminalStatus(trimmedId)) {
      return const Success(unit);
    }

    final statusPath = AgentActionElevatedConstants.statusFilePath(
      _storageContext.appDirectoryPath,
      trimmedId,
    );
    final payload = <String, Object?>{
      'version': AgentActionElevatedConstants.statusSchemaVersion,
      'executionId': trimmedId,
      'status': status.name,
      'finishedAt': _now().toUtc().toIso8601String(),
      'redactionApplied': true,
      'failureCode': failureCode,
      'failureMessage': failureMessage,
    };

    try {
      final directory = Directory(AgentActionElevatedConstants.statusDirectoryPath(_storageContext.appDirectoryPath));
      await directory.create(recursive: true);
      final tempPath = '$statusPath.tmp';
      await File(tempPath).writeAsString(jsonEncode(payload), flush: true);
      await File(tempPath).rename(statusPath);
      return const Success(unit);
    } on IOException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Unable to write elevated terminal status file.',
          cause: error,
          context: {
            'execution_id': trimmedId,
            'user_message': 'Nao foi possivel registrar o cancelamento da execucao elevada.',
          },
        ),
      );
    }
  }

  Future<bool> _hasTerminalStatus(String executionId) async {
    final statusFile = File(
      AgentActionElevatedConstants.statusFilePath(_storageContext.appDirectoryPath, executionId),
    );
    if (!statusFile.existsSync()) {
      return false;
    }

    try {
      final decoded = jsonDecode(await statusFile.readAsString()) as Map<String, dynamic>;
      final statusName = decoded['status'];
      if (statusName is! String) {
        return false;
      }
      for (final status in AgentActionExecutionStatus.values) {
        if (status.name == statusName) {
          return status.isTerminal;
        }
      }
      return false;
    } on Object {
      return false;
    }
  }
}
