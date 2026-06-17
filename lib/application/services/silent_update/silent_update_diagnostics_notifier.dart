import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show VoidCallback;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';

/// Notifies UI listeners and best-effort hub diagnostics for silent updates.
class SilentUpdateDiagnosticsNotifier {
  SilentUpdateDiagnosticsNotifier({
    required UpdateCheckDiagnostics? Function() getDiagnostics,
    VoidCallback? onDiagnosticsChanged,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
  }) : _getDiagnostics = getDiagnostics,
       _onDiagnosticsChanged = onDiagnosticsChanged,
       _diagnosticsGateway = diagnosticsGateway;

  final UpdateCheckDiagnostics? Function() _getDiagnostics;
  final VoidCallback? _onDiagnosticsChanged;
  final IAutoUpdateDiagnosticsGateway? _diagnosticsGateway;

  void notifyChanged() {
    final callback = _onDiagnosticsChanged;
    if (callback == null) return;
    try {
      callback();
    } on Object catch (error, stackTrace) {
      developer.log(
        'onDiagnosticsChanged callback threw (ignored)',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void pushBestEffort(AutoUpdateDiagnosticsSource source) {
    final gateway = _diagnosticsGateway;
    final diagnostics = _getDiagnostics();
    if (gateway == null || diagnostics == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await gateway.push(diagnostics: diagnostics, source: source);
        } on Object catch (error, stackTrace) {
          developer.log(
            'Auto-update diagnostics push threw (ignored)',
            name: 'silent_update_coordinator',
            level: 800,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }
}
