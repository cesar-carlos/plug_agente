import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:result_dart/result_dart.dart';

/// Removes stale elevated bridge JSON artifacts from the app data directory.
class CleanupExpiredElevatedBridgeArtifacts {
  CleanupExpiredElevatedBridgeArtifacts({
    required GlobalStorageContext storageContext,
    AgentActionExecutionMetricsCollector? metrics,
    DateTime Function()? now,
    bool Function()? isWindows,
  }) : _storageContext = storageContext,
       _metrics = metrics,
       _now = now ?? DateTime.now,
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final GlobalStorageContext _storageContext;
  final AgentActionExecutionMetricsCollector? _metrics;
  final DateTime Function() _now;
  final bool Function() _isWindows;

  Future<Result<int>> call({DateTime? referenceTime}) async {
    if (!_isWindows()) {
      return const Success(0);
    }

    final reference = (referenceTime ?? _now()).toUtc();
    final cutoff = reference.subtract(AgentActionElevatedConstants.bridgeArtifactMaxAge);
    var deletedCount = 0;

    final directoryPaths = <String>[
      AgentActionElevatedConstants.requestsDirectoryPath(_storageContext.appDirectoryPath),
      AgentActionElevatedConstants.statusDirectoryPath(_storageContext.appDirectoryPath),
      AgentActionElevatedConstants.cancelDirectoryPath(_storageContext.appDirectoryPath),
      AgentActionElevatedConstants.materializedDirectoryPath(_storageContext.appDirectoryPath),
    ];

    for (final directoryPath in directoryPaths) {
      deletedCount += await _purgeDirectory(Directory(directoryPath), cutoff);
    }

    if (deletedCount > 0) {
      _metrics?.recordElevatedBridgeArtifactsPurge(deletedCount);
    }
    return Success(deletedCount);
  }

  Future<int> _purgeDirectory(Directory directory, DateTime cutoffUtc) async {
    if (!directory.existsSync()) {
      return 0;
    }

    var deletedCount = 0;
    for (final entity in directory.listSync()) {
      if (entity is! File) {
        continue;
      }

      final shouldDelete = await _shouldDeleteFile(entity, cutoffUtc);
      if (!shouldDelete) {
        continue;
      }

      try {
        await entity.delete();
        deletedCount++;
      } on Object {
        // Best effort cleanup.
      }
    }

    return deletedCount;
  }

  Future<bool> _shouldDeleteFile(File file, DateTime cutoffUtc) async {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.tmp')) {
      return file.lastModifiedSync().toUtc().isBefore(cutoffUtc);
    }

    if (!name.endsWith('.json')) {
      return false;
    }

    final expiresAt = await _readExpiresAt(file);
    if (expiresAt != null) {
      return expiresAt.toUtc().isBefore(_now().toUtc()) || expiresAt.toUtc().isBefore(cutoffUtc);
    }

    return file.lastModifiedSync().toUtc().isBefore(cutoffUtc);
  }

  Future<DateTime?> _readExpiresAt(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final expiresAtRaw = decoded['expiresAt'];
      if (expiresAtRaw is! String) {
        return null;
      }
      return DateTime.tryParse(expiresAtRaw);
    } on Object {
      return null;
    }
  }
}
