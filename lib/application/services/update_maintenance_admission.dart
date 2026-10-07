import 'dart:async';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_update_maintenance_gate.dart';
import 'package:result_dart/result_dart.dart';

enum UpdateMaintenancePhase { operational, draining, resourcesClosed, dispatchUnknown, recoveryRequired }

class UpdateMaintenanceAdmission implements IUpdateMaintenanceGate {
  final Object _zoneKey = Object();
  final StreamController<UpdateMaintenancePhase> _changes = StreamController.broadcast();
  UpdateMaintenancePhase _phase = UpdateMaintenancePhase.operational;
  String? _operation;
  int _active = 0;
  UpdateMaintenancePhase get phase => _phase;
  Stream<UpdateMaintenancePhase> get changes => _changes.stream;
  bool get idle => _active == 0;
  Future<void> dispose() => _changes.close();
  bool get blocked => _phase != UpdateMaintenancePhase.operational;
  @override
  bool get allowsInternalWork =>
      _phase == UpdateMaintenancePhase.draining && Zone.current[_zoneKey] == _operation && _operation != null;

  void transition(String operation, UpdateMaintenancePhase next) {
    if (_operation != null && _operation != operation) throw StateError('Maintenance operation changed');
    if (next == UpdateMaintenancePhase.operational && _phase != UpdateMaintenancePhase.draining && blocked) {
      throw StateError('Closed or uncertain resources require process recovery');
    }
    _operation = next == UpdateMaintenancePhase.operational ? null : operation;
    _phase = next;
    _changes.add(next);
  }

  Future<T> internal<T>(String operation, Future<T> Function() action) {
    if (_operation != operation || _phase != UpdateMaintenancePhase.draining) {
      throw StateError('Internal maintenance work is not authorized');
    }
    return runZoned(action, zoneValues: {_zoneKey: operation});
  }

  @override
  Future<Result<T>> run<T extends Object>(Future<Result<T>> Function() action) async {
    try {
      return await runValue(action);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<T> runValue<T>(Future<T> Function() action) async {
    if (blocked && !allowsInternalWork) {
      throw domain.ConfigurationFailure.withContext(
        message: 'O agente está em manutenção. Aguarde a recuperação antes de continuar.',
        context: {'reason': 'update_maintenance', 'phase': _phase.name, 'retryable': true},
      );
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
    }
  }

  void checkSettingsWrite(String key) {
    // Updater evidence remains writable after SQLite closes; it is flushed before exit.
    if (blocked && !allowsInternalWork && !key.startsWith('auto_update.')) {
      throw domain.ConfigurationFailure('O agente está em manutenção. Aguarde para alterar configurações.');
    }
  }
}
