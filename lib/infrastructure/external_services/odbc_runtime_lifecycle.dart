import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Single initialization path for the shared [OdbcService] used by ODBC gateways.
final class OdbcRuntimeLifecycle {
  OdbcRuntimeLifecycle(this._service);

  final OdbcService _service;
  bool _initialized = false;
  Future<Result<void>>? _initialization;
  int _generation = 0;
  final List<void Function()> _invalidationListeners = [];

  void addInvalidationListener(void Function() listener) => _invalidationListeners.add(listener);

  bool get isInitialized => _initialized;

  Future<Result<void>> ensureInitialized({
    required String operation,
    String? userMessage,
  }) {
    if (_initialized) {
      return Future<Result<void>>.value(const Success(unit));
    }
    return _initialization ??= _initializeOnce(
      operation: operation,
      userMessage: userMessage,
    );
  }

  /// Drops cached init state after the native async worker restarts.
  void invalidateAfterWorkerRecovery() {
    _generation++;
    _initialized = false;
    _initialization = null;
    for (final listener in _invalidationListeners) {
      listener();
    }
  }

  Future<Result<void>> _initializeOnce({
    required String operation,
    String? userMessage,
  }) async {
    developer.log('Initializing ODBC environment', name: 'odbc_runtime_lifecycle');

    final generation = _generation;
    Result<void> initResult;
    try {
      initResult = await _service.initialize();
    } on Object catch (error) {
      initResult = Failure(OdbcFailureMapper.mapConnectionError(error, operation: operation));
    }
    if (generation != _generation) {
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'ODBC initialization belongs to an obsolete runtime generation',
          context: const {'retryable': false, 'reason': 'odbc_generation_changed'},
        ),
      );
    }
    return initResult.fold(
      (_) {
        _initialized = true;
        developer.log(
          'ODBC initialized successfully',
          name: 'odbc_runtime_lifecycle',
          level: 500,
        );
        return const Success(unit);
      },
      (error) {
        _initialization = null;
        developer.log(
          'ODBC initialization failed',
          name: 'odbc_runtime_lifecycle',
          level: 1000,
          error: error,
        );
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: operation,
            context: {
              'reason': OdbcContextConstants.odbcInitializationFailedReason,
              'user_message': userMessage ?? 'Não foi possível inicializar o ambiente ODBC neste computador.',
            },
          ),
        );
      },
    );
  }
}
