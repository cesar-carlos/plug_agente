import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef RpcIdempotencyExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Runs best-effort expired-row purge on a wall-clock timer after bootstrap.
///
/// Bootstrap already invokes the cleanup use case once; this avoids leaving
/// expired rows in SQLite until the next restart when traffic is sparse.
class RpcIdempotencyCachePeriodicPurge {
  RpcIdempotencyCachePeriodicPurge(
    RpcIdempotencyExpiredPurge purge, {
    Duration interval = ConnectionConstants.rpcIdempotencyExpiredPurgeInterval,
  }) : _runner = PeriodicPurgeRunner(
         purge: () => purge(),
         interval: interval,
         logName: 'rpc_idempotency_cache_periodic_purge',
         successLogMessage: (int count) => 'Purged $count expired RPC idempotency cache row(s) (periodic)',
         failureLogMessage: 'Periodic RPC idempotency cache purge failed (continuing)',
       );

  final PeriodicPurgeRunner _runner;

  bool get isRunning => _runner.isRunning;

  void start() => _runner.start();

  void stop() => _runner.stop();

  Future<void> purgeNow() => _runner.purgeNow();
}
