import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:plug_agente/domain/services/i_installation_preparation_monitor.dart';

class WindowsInstallationPreparationMonitor implements IInstallationPreparationMonitor {
  WindowsInstallationPreparationMonitor(this.preparation, {MethodChannel? channel, this.onStateChanged})
    : _channel = channel ?? const MethodChannel('plug_agente/installation');
  final IInstallationPreparation preparation;
  final MethodChannel _channel;
  final Future<void> Function(InstallationPreparationState)? onStateChanged;
  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;
  bool _starting = false;

  @override
  Future<void> start() async {
    if (_timer != null || _stopped || _starting) return;
    _starting = true;
    try {
      if (await _channel.invokeMethod<bool>('enable') != true || _stopped) return;
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => unawaited(_poll()));
    } on Object catch (error, stack) {
      developer.log('Installation channel unavailable', error: error, stackTrace: stack);
    } finally {
      _starting = false;
    }
  }

  Future<void> _poll() async {
    if (_stopped) return;
    if (_busy) {
      try {
        if (await _channel.invokeMethod<bool>('cancelled') == true) preparation.cancel();
      } on Object catch (error, stack) {
        developer.log('Installation cancellation unconfirmed', error: error, stackTrace: stack);
      }
      return;
    }
    _busy = true;
    String? operation;
    try {
      operation = await _channel.invokeMethod<String>('poll');
      if (_stopped || operation == null || operation.isEmpty) return;
      unawaited(_notify(InstallationPreparationState.waiting));
      if (await _channel.invokeMethod<bool>('cancelled') == true) preparation.cancel();
      final result = await preparation.prepare(operation);
      if (result.isError()) developer.log('Installation preparation failed', error: result.exceptionOrNull());
      await _report(operation);
      unawaited(_notify(preparation.state));
      if (!_stopped && preparation.state == InstallationPreparationState.closing) {
        final closed = await preparation.close();
        if (closed.isError()) {
          developer.log('Installation close failed', error: closed.exceptionOrNull());
          await _report(operation);
          unawaited(_notify(preparation.state));
        }
      }
    } on Object catch (error, stack) {
      developer.log('Installation coordination unconfirmed', error: error, stackTrace: stack);
    } finally {
      _busy = false;
    }
  }

  Future<void> _report(String operation) =>
      _channel.invokeMethod<void>('report', jsonEncode({'operation': operation, 'state': preparation.state.name}));

  Future<void> _notify(InstallationPreparationState state) async {
    try {
      await onStateChanged?.call(state);
    } on Object catch (error, stack) {
      developer.log('Installation notification failed', error: error, stackTrace: stack);
    }
  }

  @override
  void stop() {
    _stopped = true;
    if (_busy) preparation.cancel();
    _timer?.cancel();
    _timer = null;
  }
}
