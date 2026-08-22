import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Tracks native streaming disconnects after the caller stops waiting.
///
/// `odbc_fast` 4.5.1 exposes `disconnect(connectionId)` and
/// `cancelStream(streamId)` only. High-level `streamQuery*` APIs do not return
/// a stream id, and disconnect has no force-close or timeout argument. A Dart
/// `.timeout()` must not abandon the underlying future: this tracker keeps it
/// until the native call completes so the handle is not forgotten.
final class OdbcStreamingDisconnectTracker {
  OdbcStreamingDisconnectTracker({
    this.maxInFlight = defaultMaxInFlight,
    this.observedTimeout = defaultObservedTimeout,
  });

  static const int defaultMaxInFlight = 16;
  static const Duration defaultObservedTimeout = Duration(seconds: 8);

  final int maxInFlight;
  final Duration observedTimeout;
  final Map<String, Future<Result<void>>> _inFlight = <String, Future<Result<void>>>{};

  int get inFlightCount => _inFlight.length;

  Future<Result<void>> run({
    required String connectionId,
    required Future<Result<void>> Function(String connectionId) disconnect,
    Duration? timeout,
    void Function()? onTimeout,
    void Function()? onFailure,
    void Function()? onSaturated,
  }) async {
    if (connectionId.isEmpty) {
      return const Success(unit);
    }

    if (_inFlight.length >= maxInFlight) {
      onSaturated?.call();
      developer.log(
        'Streaming disconnect backlog is saturated '
        '(in_flight=${_inFlight.length}, max=$maxInFlight); still starting disconnect for $connectionId',
        name: 'odbc_streaming_disconnect_tracker',
        level: 900,
      );
    }

    final work = disconnect(connectionId);
    _inFlight[connectionId] = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_inFlight[connectionId], work)) {
          _inFlight.remove(connectionId);
        }
      }),
    );

    try {
      final result = await work.timeout(timeout ?? observedTimeout);
      return await result.fold(
        (_) => const Success(unit),
        (error) {
          if (OdbcErrorInspector.isInvalidConnectionId(error)) {
            return const Success(unit);
          }
          onFailure?.call();
          developer.log(
            'Streaming disconnect failed for $connectionId; handle remains discarded',
            name: 'odbc_streaming_disconnect_tracker',
            level: 900,
            error: error,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'streaming_disconnect',
              context: {
                'reason': OdbcContextConstants.streamCancelDisconnectFailedReason,
                'discarded': true,
              },
            ),
          );
        },
      );
    } on TimeoutException catch (error) {
      onTimeout?.call();
      developer.log(
        'Streaming disconnect timed out for $connectionId; native call stays tracked until completion',
        name: 'odbc_streaming_disconnect_tracker',
        level: 900,
        error: error,
      );
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'Streaming disconnect did not finish within the expected time',
          cause: error,
          context: {
            'reason': OdbcContextConstants.streamCancelDisconnectTimeoutReason,
            'connectionId': connectionId,
            'discarded': true,
            'in_flight': true,
            'timeout_ms': (timeout ?? observedTimeout).inMilliseconds,
          },
        ),
      );
    }
  }

  /// Waits for tracked disconnects. A [timeout] logs leftovers instead of
  /// hanging forever; 4.5.1 has no hard-free API for a stuck disconnect.
  Future<void> drain({Duration? timeout}) async {
    if (_inFlight.isEmpty) {
      return;
    }

    final pending = List<Future<Result<void>>>.of(_inFlight.values);
    if (timeout == null) {
      await Future.wait(pending);
      return;
    }

    try {
      await Future.wait(pending).timeout(timeout);
    } on TimeoutException {
      developer.log(
        'Streaming disconnect drain timed out with ${_inFlight.length} native handle(s) still in flight '
        '(${OdbcContextConstants.streamDisconnectStillInFlightReason})',
        name: 'odbc_streaming_disconnect_tracker',
        level: 900,
      );
    }
  }
}
