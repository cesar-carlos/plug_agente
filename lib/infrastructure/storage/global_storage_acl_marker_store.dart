import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/global_storage_acl_constants.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

/// Persists and reads the ACL normalization marker under the app data directory.
class GlobalStorageAclMarkerStore {
  GlobalStorageAclMarkerStore({
    String Function()? appVersionReader,
  }) : _appVersionReader = appVersionReader ?? (() => AppConstants.appVersion);

  final String Function() _appVersionReader;

  String markerPathFor(String appDirectoryPath) {
    return p.join(appDirectoryPath, GlobalStorageAclConstants.markerFileName);
  }

  bool isFresh(String appDirectoryPath) {
    final file = File(markerPathFor(appDirectoryPath));
    if (!file.existsSync()) {
      return false;
    }

    try {
      final payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final markerVersion = payload['app_version'] as String?;
      return markerVersion == _appVersionReader();
    } on Object {
      return false;
    }
  }

  GlobalStorageAclMarkerSnapshot? read(String appDirectoryPath) {
    final file = File(markerPathFor(appDirectoryPath));
    if (!file.existsSync()) {
      return null;
    }

    try {
      final payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return GlobalStorageAclMarkerSnapshot(
        normalizedAt: DateTime.tryParse(payload['normalized_at'] as String? ?? ''),
        appVersion: payload['app_version'] as String?,
        lastOutcome: payload['last_outcome'] as String?,
      );
    } on Object {
      return null;
    }
  }

  Future<void> write({
    required String appDirectoryPath,
    required IcaclsGrantOutcome outcome,
  }) async {
    final payload = <String, Object?>{
      'normalized_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': _appVersionReader(),
      'last_outcome': outcome.diagnosticName,
    };
    final file = File(markerPathFor(appDirectoryPath));
    await file.writeAsString(jsonEncode(payload), flush: true);
  }
}

class GlobalStorageAclMarkerSnapshot {
  const GlobalStorageAclMarkerSnapshot({
    this.normalizedAt,
    this.appVersion,
    this.lastOutcome,
  });

  final DateTime? normalizedAt;
  final String? appVersion;
  final String? lastOutcome;
}
