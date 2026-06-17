import 'dart:developer' as developer;

import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';

/// Validates UAC detector wiring for runtimes that support auto-update.
class SilentUpdateUacGuard {
  const SilentUpdateUacGuard({
    required RuntimeCapabilities capabilities,
    required IUacDetector uacDetector,
  }) : _capabilities = capabilities,
       _uacDetector = uacDetector;

  final RuntimeCapabilities _capabilities;
  final IUacDetector _uacDetector;

  /// Logs a loud warning when the runtime supports auto-update yet the
  /// injected detector is the no-op fallback.
  void warnIfDetectorIsNoopOnSupportedRuntime() {
    if (!_capabilities.supportsAutoUpdate) return;
    if (_uacDetector is! NoopUacDetector) return;
    developer.log(
      'SilentUpdateCoordinator is using NoopUacDetector on a runtime '
      'that supports auto-update (supportsAutoUpdate=true). The UAC '
      'gate will never engage; verify the DI registrar wires a real '
      'detector (e.g. WindowsUacDetector) on Windows.',
      name: 'silent_update_coordinator',
      level: 900,
    );
  }
}
