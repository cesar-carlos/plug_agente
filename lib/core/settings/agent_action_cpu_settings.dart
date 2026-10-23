import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:result_dart/result_dart.dart';

/// Local limit for each newly started action tree. Zero preserves Windows scheduling.
class AgentActionCpuSettings {
  AgentActionCpuSettings(this._store);
  final IAppSettingsStore _store;
  int? _lastConfirmedLimit;
  static const key = 'agent_action_cpu_limit_percent';

  int get limitPercent {
    final value = _lastConfirmedLimit ?? _store.getInt(key) ?? 0;
    return value;
  }

  Future<Result<void>> save(int percent) async {
    if (percent < 0 || percent > 100) {
      return Failure(ActionValidationFailure('Informe um limite de CPU entre 1 e 100%, ou 0 para desativar.'));
    }
    final previous = limitPercent;
    try {
      await _store.setInt(key, percent);
      await _store.flushPendingPersistence();
      if (_store.lastPersistError case final Object error) throw StateError('$error');
      _lastConfirmedLimit = percent;
      return const Success(unit);
    } on Object catch (error) {
      _lastConfirmedLimit = previous;
      return Failure(
        ActionRuntimeFailure.withContext(message: 'Não foi possível salvar o limite de CPU.', cause: error),
      );
    }
  }
}
