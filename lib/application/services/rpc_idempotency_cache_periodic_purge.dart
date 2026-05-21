import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef RpcIdempotencyExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Runs best-effort expired-row purge on a wall-clock timer after bootstrap.
///
/// Bootstrap already invokes the cleanup use case once; this avoids leaving
/// expired rows in SQLite until the next restart when traffic is sparse.
class RpcIdempotencyCachePeriodicPurge {
  RpcIdempotencyCachePeriodicPurge(
    this._purge, {
    Duration interval = ConnectionConstants.rpcIdempotencyExpiredPurgeInterval,
  }) : _interval = interval;

  final RpcIdempotencyExpiredPurge _purge;
  final Duration _interval;
  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) {
      unawaited(purgeNow());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> purgeNow() async {
    try {
      final result = await _purge();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count expired RPC idempotency cache row(s) (periodic)',
              name: 'rpc_idempotency_cache_periodic_purge',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Periodic RPC idempotency cache purge failed (continuing)',
            name: 'rpc_idempotency_cache_periodic_purge',
            level: 900,
            error: failure,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Periodic RPC idempotency cache purge failed (continuing)',
        name: 'rpc_idempotency_cache_periodic_purge',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
