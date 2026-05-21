import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_materialized_reader.dart';
import 'package:plug_agente_elevated_runner/src/elevated_process_runner.dart';
import 'package:plug_agente_elevated_runner/src/elevated_sqlite_store.dart';
import 'package:plug_agente_elevated_runner/src/elevated_status_writer.dart';

class ElevatedRequestProcessor {
  ElevatedRequestProcessor({
    required this.appDirectoryPath,
    ElevatedSqliteStore? store,
    ElevatedProcessRunner? processRunner,
    ElevatedStatusWriter? statusWriter,
    DateTime Function()? now,
  }) : _store = store ?? ElevatedSqliteStore(appDirectoryPath: appDirectoryPath),
       _processRunner = processRunner ?? ElevatedProcessRunner(appDirectoryPath: appDirectoryPath),
       _statusWriter = statusWriter ?? ElevatedStatusWriter(appDirectoryPath: appDirectoryPath),
       _now = now ?? DateTime.now;

  final String appDirectoryPath;
  final ElevatedSqliteStore _store;
  final ElevatedProcessRunner _processRunner;
  final ElevatedStatusWriter _statusWriter;
  final DateTime Function() _now;

  Future<int> processPendingRequests() async {
    final requestsDirectory = Directory(ElevatedContract.requestsDirectory(appDirectoryPath));
    if (!requestsDirectory.existsSync()) {
      return 0;
    }

    final files = requestsDirectory
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.endsWith('.json'))
        .toList()
      ..sort((File left, File right) => left.path.compareTo(right.path));

    var processed = 0;
    for (final file in files) {
      final handled = await _processRequestFile(file);
      if (handled) {
        processed++;
      }
    }
    return processed;
  }

  Future<bool> _processRequestFile(File file) async {
    final executionId = _executionIdFromFileName(file);
    if (executionId == null) {
      await _safeDelete(file);
      return false;
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on Object {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: 'Request file is not valid JSON.',
      );
      await _safeDelete(file);
      return true;
    }

    final validationError = _validateRequestPayload(payload, executionId);
    if (validationError != null) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: validationError,
      );
      await _safeDelete(file);
      return true;
    }

    final requestNonce = (payload['nonce'] as String).trim();
    final materializedReader = ElevatedMaterializedReader(appDirectoryPath: appDirectoryPath);
    final materialized = materializedReader.read(executionId);
    if (materialized == null) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: 'Materialized launch plan was not found.',
      );
      await _safeDelete(file);
      return true;
    }
    if (_now().toUtc().isAfter(materialized.expiresAt.toUtc())) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: 'Materialized launch plan expired before processing.',
      );
      await materializedReader.delete(executionId);
      await _safeDelete(file);
      return true;
    }
    if (materialized.nonce != requestNonce) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: 'Materialized launch plan nonce does not match request.',
      );
      await materializedReader.delete(executionId);
      await _safeDelete(file);
      return true;
    }

    final context = _store.loadExecutionContext(executionId);
    if (context == null) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_NOT_FOUND',
        failureMessage: 'Execution or action definition was not found in local storage.',
      );
      await _safeDelete(file);
      return true;
    }

    if (context.actionType != materialized.actionType) {
      await _writeFailure(
        executionId: executionId,
        failureCode: 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
        failureMessage: 'Materialized action type does not match execution record.',
      );
      await materializedReader.delete(executionId);
      await _safeDelete(file);
      return true;
    }

    final status = await _processRunner.run(
      context: context,
      launch: materialized.launch,
    );
    await _statusWriter.write(status);
    await _safeDelete(file);
    return true;
  }

  String? _validateRequestPayload(Map<String, dynamic> payload, String executionId) {
    final version = payload['version'];
    if (version is! num || version.toInt() != ElevatedContract.requestSchemaVersion) {
      return 'Unsupported request schema version.';
    }

    final payloadExecutionId = payload['executionId'];
    if (payloadExecutionId is! String || payloadExecutionId.trim() != executionId) {
      return 'Request executionId does not match file name.';
    }

    final nonce = payload['nonce'];
    if (nonce is! String || nonce.trim().isEmpty) {
      return 'Request nonce is missing.';
    }

    final createdAtRaw = payload['createdAt'];
    if (createdAtRaw is! String) {
      return 'Request createdAt is missing.';
    }
    if (DateTime.tryParse(createdAtRaw) == null) {
      return 'Request createdAt is invalid.';
    }

    final expiresAtRaw = payload['expiresAt'];
    if (expiresAtRaw is! String) {
      return 'Request expiration is missing.';
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) {
      return 'Request expiration is invalid.';
    }
    if (_now().toUtc().isAfter(expiresAt.toUtc())) {
      return 'Request expired before processing.';
    }

    return null;
  }

  String? _executionIdFromFileName(File file) {
    final baseName = file.uri.pathSegments.last;
    if (!baseName.endsWith('.json')) {
      return null;
    }
    final executionId = baseName.substring(0, baseName.length - '.json'.length).trim();
    if (executionId.isEmpty || executionId.contains('..')) {
      return null;
    }
    return executionId;
  }

  Future<void> _writeFailure({
    required String executionId,
    required String failureCode,
    required String failureMessage,
  }) async {
    await _statusWriter.write(
      ElevatedStatusPayload(
        executionId: executionId,
        status: 'failed',
        finishedAt: _now(),
        failureCode: failureCode,
        failureMessage: failureMessage,
      ),
    );
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Best effort cleanup.
    }
  }
}
