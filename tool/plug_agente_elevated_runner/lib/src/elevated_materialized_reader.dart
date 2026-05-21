import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_launch_spec.dart';

class ElevatedMaterializedPlan {
  const ElevatedMaterializedPlan({
    required this.executionId,
    required this.nonce,
    required this.expiresAt,
    required this.actionType,
    required this.launch,
  });

  final String executionId;
  final String nonce;
  final DateTime expiresAt;
  final String actionType;
  final ElevatedLaunchSpec launch;
}

class ElevatedMaterializedReader {
  const ElevatedMaterializedReader({required this.appDirectoryPath});

  final String appDirectoryPath;

  ElevatedMaterializedPlan? read(String executionId) {
    final file = File(ElevatedContract.materializedFilePath(appDirectoryPath, executionId));
    if (!file.existsSync()) {
      return null;
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final version = decoded['version'];
      if (version is! num || version.toInt() != ElevatedContract.materializedSchemaVersion) {
        return null;
      }

      final payloadExecutionId = decoded['executionId'];
      final nonce = decoded['nonce'];
      final expiresAtRaw = decoded['expiresAt'];
      final actionType = decoded['actionType'];
      final launch = decoded['launch'];
      if (payloadExecutionId is! String ||
          nonce is! String ||
          expiresAtRaw is! String ||
          actionType is! String ||
          launch is! Map) {
        return null;
      }

      if (payloadExecutionId.trim() != executionId.trim()) {
        return null;
      }

      final expiresAt = DateTime.tryParse(expiresAtRaw);
      if (expiresAt == null) {
        return null;
      }

      return ElevatedMaterializedPlan(
        executionId: payloadExecutionId.trim(),
        nonce: nonce.trim(),
        expiresAt: expiresAt,
        actionType: actionType.trim(),
        launch: ElevatedLaunchSpec.fromJson(Map<String, dynamic>.from(launch)),
      );
    } on Object {
      return null;
    }
  }

  Future<void> delete(String executionId) async {
    final file = File(ElevatedContract.materializedFilePath(appDirectoryPath, executionId));
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Best effort cleanup.
    }
  }
}
