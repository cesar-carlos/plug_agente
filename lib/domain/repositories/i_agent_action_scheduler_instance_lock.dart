import 'package:result_dart/result_dart.dart';

/// Exclusive lock for the in-process agent action trigger scheduler.
///
/// Prevents two Plug Agente processes sharing the same global data folder from
/// both running temporal triggers against the same Drift store.
abstract interface class IAgentActionSchedulerInstanceLock {
  bool get isHeld;

  Future<Result<Unit>> tryAcquire();

  Future<void> release();
}
