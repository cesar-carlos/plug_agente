import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';

class ElevatedStatusPayload {
  const ElevatedStatusPayload({
    required this.executionId,
    required this.status,
    required this.finishedAt,
    this.exitCode,
    this.failureCode,
    this.failureMessage,
    this.stdoutText,
    this.stderrText,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.processCommandPreview,
    this.redactionApplied = true,
  });

  final String executionId;
  final String status;
  final DateTime finishedAt;
  final int? exitCode;
  final String? failureCode;
  final String? failureMessage;
  final String? stdoutText;
  final String? stderrText;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final String? processCommandPreview;
  final bool redactionApplied;
}

class ElevatedStatusWriter {
  const ElevatedStatusWriter({required this.appDirectoryPath});

  final String appDirectoryPath;

  Future<void> write(ElevatedStatusPayload payload) async {
    final directory = Directory(
      ElevatedContract.statusDirectory(appDirectoryPath),
    );
    await directory.create(recursive: true);
    final path = ElevatedContract.statusFilePath(
      appDirectoryPath,
      payload.executionId,
    );
    final tempPath = '$path.tmp';
    final body = <String, Object?>{
      'version': ElevatedContract.statusSchemaVersion,
      'executionId': payload.executionId,
      'status': payload.status,
      'finishedAt': payload.finishedAt.toUtc().toIso8601String(),
      'redactionApplied': payload.redactionApplied,
      if (payload.exitCode != null) 'exitCode': payload.exitCode,
      if (payload.failureCode != null) 'failureCode': payload.failureCode,
      if (payload.failureMessage != null)
        'failureMessage': payload.failureMessage,
      if (payload.stdoutText != null) 'stdoutText': payload.stdoutText,
      if (payload.stderrText != null) 'stderrText': payload.stderrText,
      if (payload.stdoutTruncated) 'stdoutTruncated': true,
      if (payload.stderrTruncated) 'stderrTruncated': true,
      if (payload.processCommandPreview != null)
        'processCommandPreview': payload.processCommandPreview,
    };
    final file = File(tempPath);
    await file.writeAsString(jsonEncode(body));
    await file.rename(path);
  }
}
