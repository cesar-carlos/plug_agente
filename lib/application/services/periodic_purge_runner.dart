import 'dart:async';
import 'dart:developer' as developer;

import 'package:result_dart/result_dart.dart';

typedef PeriodicPurge = Future<Result<int>> Function();

/// Schedules best-effort purge callbacks on a wall-clock timer with standardized logging.
class PeriodicPurgeRunner {
  PeriodicPurgeRunner({
    required PeriodicPurge purge,
    required Duration interval,
    required String logName,
    required String Function(int count) successLogMessage,
    required String failureLogMessage,
  }) : _purge = purge,
       _interval = interval,
       _logName = logName,
       _successLogMessage = successLogMessage,
       _failureLogMessage = failureLogMessage;

  final PeriodicPurge _purge;
  final Duration _interval;
  final String _logName;
  final String Function(int count) _successLogMessage;
  final String _failureLogMessage;
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

  void dispose() => stop();

  Future<void> purgeNow() async {
    try {
      final result = await _purge();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              _successLogMessage(count),
              name: _logName,
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            _failureLogMessage,
            name: _logName,
            level: 900,
            error: failure,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        _failureLogMessage,
        name: _logName,
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
