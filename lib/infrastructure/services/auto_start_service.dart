import 'dart:developer' as developer;

import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoStartService implements IStartupService {
  AutoStartService(this._prefs);

  final SharedPreferences _prefs;
  static const _startWithWindowsKey = 'settings.start_with_windows';

  @override
  Future<Result<bool>> isEnabled() async {
    final enabled = _prefs.getBool(_startWithWindowsKey) ?? false;

    developer.log(
      'Auto-start status: $enabled',
      name: 'startup_service',
      level: 800,
    );

    return Success(enabled);
  }

  @override
  Future<Result<Unit>> enable() async {
    try {
      await registerBootCallback(_bootCallback);

      developer.log(
        'Startup enabled successfully via registerBootCallback',
        name: 'startup_service',
        level: 800,
      );

      return const Success(unit);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to enable startup',
        name: 'startup_service',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Falha ao habilitar inicialização automática',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> disable() async {
    try {
      final openResult = await openSystemSettings();

      return openResult.fold(
        (_) {
          developer.log(
            'Opened system settings for manual autostart disable',
            name: 'startup_service',
            level: 800,
          );
          return const Success(unit);
        },
        Failure.new,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to disable startup',
        name: 'startup_service',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Falha ao desabilitar inicialização automática',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> openSystemSettings() async {
    try {
      await getAutoStartPermission();

      developer.log(
        'Opened system startup settings',
        name: 'startup_service',
        level: 800,
      );

      return const Success(unit);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to open system settings',
        name: 'startup_service',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Falha ao abrir configurações do sistema',
          cause: e,
        ),
      );
    }
  }

  static void _bootCallback() {
    developer.log(
      'App started via boot callback',
      name: 'startup_service',
      level: 800,
    );
  }
}
