import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:result_dart/result_dart.dart';

/// Tracks only read waits, never process execution or input delivery.
///
/// Early controls survive asynchronous request decoding for one request deadline.
/// Active leases cannot expire: their owner must release them after dispatch.
final class ActionIoReadCancellations {
  ActionIoReadCancellations({Duration Function()? elapsed})
    : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDuration;

  static const capacity = 256;
  static const retention = Duration(seconds: 30);
  final Duration Function() _elapsed;
  final _active = <(int, Object), ActionIoReadLease>{};
  final _early = <(int, Object), Duration>{};

  Result<ActionIoReadLease> acquire({required int generation, required Object requestId}) {
    _prune();
    final key = (generation, requestId);
    if (_active.containsKey(key)) return Failure(_failure('ACTION_IO_READ_ALREADY_ACTIVE'));
    final cancelled = _early.containsKey(key);
    if (!cancelled && _active.length + _early.length >= capacity) {
      return Failure(_failure('ACTION_IO_READER_LIMIT'));
    }
    _early.remove(key);
    final lease = ActionIoReadLease._(cancelled);
    _active[key] = lease;
    lease._release = () {
      if (identical(_active[key], lease)) _active.remove(key);
    };
    return Success(lease);
  }

  Result<Unit> cancel({required int generation, required Object requestId}) {
    _prune();
    final key = (generation, requestId);
    final active = _active[key];
    if (active != null) {
      active._cancelled = true;
      return const Success(unit);
    }
    if (_early.containsKey(key)) return const Success(unit);
    if (_active.length + _early.length >= capacity) {
      return Failure(_failure('ACTION_IO_READER_LIMIT'));
    }
    _early[key] = _elapsed() + retention;
    return const Success(unit);
  }

  void reset() {
    for (final lease in _active.values) {
      lease._cancelled = true;
    }
    _active.clear();
    _early.clear();
  }

  void _prune() {
    final now = _elapsed();
    _early.removeWhere((_, expires) => expires <= now);
  }

  ActionRuntimeFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The read wait could not be registered.',
    code: code,
    context: {'retryable': false},
  );
}

final class ActionIoReadLease {
  ActionIoReadLease._(this._cancelled);
  bool _cancelled;
  void Function()? _release;
  bool get isCancelled => _cancelled;

  void release() {
    _release?.call();
    _release = null;
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
