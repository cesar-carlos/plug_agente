import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_status_file_writer.dart';
import 'package:result_dart/result_dart.dart';

/// Signals cancellation to the elevated helper and removes pending request files.
class ElevatedActionExecutionCanceller implements IElevatedActionExecutionCanceller {
  ElevatedActionExecutionCanceller({
    required GlobalStorageContext storageContext,
    ElevatedActionStatusFileWriter? statusFileWriter,
    DateTime Function()? now,
  }) : _storageContext = storageContext,
       _statusFileWriter = statusFileWriter ?? ElevatedActionStatusFileWriter(storageContext: storageContext),
       _now = now ?? DateTime.now;

  final GlobalStorageContext _storageContext;
  final ElevatedActionStatusFileWriter _statusFileWriter;
  final DateTime Function() _now;

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
  }) async {
    final trimmedId = executionId.trim();
    if (trimmedId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Execution id is required to cancel an elevated action.',
          context: const {
            'field': 'executionId',
            'user_message': 'Informe a execucao que sera cancelada.',
          },
        ),
      );
    }

    final cancelWriteResult = await _writeCancelMarker(trimmedId);
    if (cancelWriteResult.isError()) {
      return Failure(cancelWriteResult.exceptionOrNull()!);
    }

    await _deleteIfExists(
      File(AgentActionElevatedConstants.requestFilePath(_storageContext.appDirectoryPath, trimmedId)),
    );
    await _deleteIfExists(
      File(AgentActionElevatedConstants.materializedFilePath(_storageContext.appDirectoryPath, trimmedId)),
    );

    final statusWriteResult = await _statusFileWriter.writeTerminalStatusIfAbsent(
      executionId: trimmedId,
      status: AgentActionExecutionStatus.killed,
      failureCode: AgentActionFailureCode.executionKilled,
      failureMessage: 'Elevated execution cancel requested.',
    );
    if (statusWriteResult.isError()) {
      return Failure(statusWriteResult.exceptionOrNull()!);
    }

    return Success(
      AgentActionCancellationResult(
        executionId: trimmedId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        message: 'Elevated execution cancel requested.',
      ),
    );
  }

  Future<Result<void>> _writeCancelMarker(String executionId) async {
    final cancelPath = AgentActionElevatedConstants.cancelFilePath(
      _storageContext.appDirectoryPath,
      executionId,
    );
    // Echo the materialized nonce so the helper can reject forged cancel
    // markers written by other processes with directory write access.
    final materializedNonce = await _readMaterializedNonce(executionId);
    final payload = <String, Object?>{
      'version': AgentActionElevatedConstants.cancelSchemaVersion,
      'executionId': executionId,
      'requestedAt': _now().toUtc().toIso8601String(),
      'nonce': ?materializedNonce,
    };

    try {
      final directory = Directory(AgentActionElevatedConstants.cancelDirectoryPath(_storageContext.appDirectoryPath));
      await directory.create(recursive: true);
      final tempPath = '$cancelPath.tmp';
      await File(tempPath).writeAsString(jsonEncode(payload), flush: true);
      await File(tempPath).rename(cancelPath);
      return const Success(unit);
    } on IOException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Unable to write elevated cancel marker file.',
          cause: error,
          context: {
            'execution_id': executionId,
            'user_message': 'Nao foi possivel sinalizar o cancelamento para o executor elevado.',
          },
        ),
      );
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Best effort cleanup.
    }
  }

  /// Reads the nonce previously written into the materialized launch plan.
  /// Returns `null` when the file is absent, unreadable, or does not carry
  /// the field; helper falls back to legacy "execution-id only" behavior in
  /// that case.
  Future<String?> _readMaterializedNonce(String executionId) async {
    try {
      final file = File(
        AgentActionElevatedConstants.materializedFilePath(_storageContext.appDirectoryPath, executionId),
      );
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final nonce = decoded['nonce'];
      if (nonce is String && nonce.isNotEmpty) {
        return nonce;
      }
      return null;
    } on Object {
      return null;
    }
  }
}
