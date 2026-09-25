import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';

/// Clears the installer auto-start handshake without failing the caller.
///
/// A marker that cannot be deleted only means the request is retried on the
/// next boot, so the failure is logged instead of propagated.
Future<void> clearInstallerAutostartRequestBestEffort(
  IInstallerAutostartRequestStore store, {
  required String logName,
}) async {
  try {
    await store.clearPendingRequest();
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to clear installer auto-start request',
      name: logName,
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
