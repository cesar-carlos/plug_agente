import 'dart:convert';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';
import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_pending_silent_update_store.dart';
import 'package:plug_agente/domain/repositories/i_update_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

const String pendingSilentUpdateSettingsKey = AutoUpdateSettingsKeys.pendingSilentUpdate;

class SettingsBackedPendingSilentUpdateStore implements IPendingSilentUpdateStore {
  SettingsBackedPendingSilentUpdateStore({required IUpdatePreferencesRepository preferences})
    : _preferences = preferences;
  final IUpdatePreferencesRepository _preferences;
  domain.ConfigurationFailure? _writeFailure;

  @override
  Future<Result<PendingSilentUpdateSnapshot>> load() async {
    if (_writeFailure case final failure?) return Failure(failure);
    String? raw;
    try {
      raw = _preferences.readPendingSilentUpdateJson();
    } on domain.Failure catch (error) {
      return Failure(error);
    } on Object catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Não foi possível ler a atualização pendente.',
          cause: error,
          context: const {'reason': 'pending_read_failed'},
        ),
      );
    }
    if (raw == null) return const Success(PendingSilentUpdateSnapshot(null));
    try {
      final decoded = jsonDecode(raw);
      final pending = decoded is Map<String, dynamic> ? PendingSilentUpdate.fromJson(decoded) : null;
      if (pending == null) throw const FormatException('Invalid pending record');
      return Success(PendingSilentUpdateSnapshot(pending));
    } on Object catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'O registro da atualização está inválido. Verifique a recuperação.',
          cause: error,
          context: const {'reason': 'pending_corrupted', 'outcome_unknown': true},
        ),
      );
    }
  }

  Future<Result<void>> _persist(Future<void> Function() change) async {
    try {
      await change();
      await _preferences.flushPendingPersistence();
      if (_preferences.lastPersistError case final error?) {
        throw domain.ConfigurationFailure.withContext(message: 'Não foi possível salvar a atualização.', cause: error);
      }
      _writeFailure = null;
      return const Success(unit);
    } on Object catch (error) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Não foi possível salvar o estado da atualização.',
        cause: error,
        context: const {'reason': 'pending_persistence_unconfirmed'},
      );
      _writeFailure = failure;
      return Failure(failure);
    }
  }

  @override
  Future<Result<void>> save(PendingSilentUpdate pending) =>
      _persist(() => _preferences.writePendingSilentUpdateJson(jsonEncode(pending.toJson())));
  @override
  Future<Result<void>> remove() => _persist(_preferences.clearPendingSilentUpdateJson);
}
