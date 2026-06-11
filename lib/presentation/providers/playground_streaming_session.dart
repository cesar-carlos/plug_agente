import 'dart:async';

import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef PlaygroundStreamingChunkHandler = Future<void> Function(List<Map<String, dynamic>> chunk);
typedef PlaygroundStreamingNotifyListener = void Function();

final class PlaygroundStreamingSession {
  PlaygroundStreamingSession({
    required ExecuteStreamingQuery executeStreamingQuery,
    Duration uiUpdateInterval = const Duration(milliseconds: 200),
    int progressEstimateOffset = 100,
  }) : _executeStreamingQuery = executeStreamingQuery,
       _uiUpdateInterval = uiUpdateInterval,
       _progressEstimateOffset = progressEstimateOffset;

  final ExecuteStreamingQuery _executeStreamingQuery;
  final Duration _uiUpdateInterval;
  final int _progressEstimateOffset;

  bool _streamingCapCancelRequested = false;
  bool _streamingStoppedByCap = false;
  DateTime _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get streamingCapCancelRequested => _streamingCapCancelRequested;
  bool get streamingStoppedByCap => _streamingStoppedByCap;

  void resetCapState() {
    _streamingCapCancelRequested = false;
    _streamingStoppedByCap = false;
    _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  double progressForRowCount(int rowCount) {
    return rowCount / (rowCount + _progressEstimateOffset);
  }

  Future<void> processChunk({
    required List<Map<String, dynamic>> chunk,
    required List<Map<String, dynamic>> results,
    required void Function(int rowsProcessed, double progress) onProgress,
    required PlaygroundStreamingNotifyListener notifyProgress,
    required void Function(int cap) onRowCapReached,
  }) async {
    if (_streamingCapCancelRequested) {
      return;
    }
    final cap = ConnectionConstants.playgroundStreamingMaxResultRows;
    final remaining = cap - results.length;
    if (remaining <= 0) {
      onRowCapReached(cap);
      _requestStopAtRowCap(cap);
      return;
    }
    if (chunk.length > remaining) {
      results.addAll(chunk.sublist(0, remaining));
    } else {
      results.addAll(chunk);
    }
    final rowsProcessed = results.length;
    onProgress(rowsProcessed, progressForRowCount(rowsProcessed));
    _notifyProgressIfNeeded(notifyProgress);
    if (results.length >= cap) {
      onRowCapReached(cap);
      _requestStopAtRowCap(cap);
    }
  }

  Future<rd.Result<void>> executeStreamingQuery({
    required String query,
    required String connectionString,
    required PlaygroundStreamingChunkHandler onChunk,
  }) {
    return _executeStreamingQuery(query, connectionString, onChunk);
  }

  Future<void> cancelActiveStream({StreamingCancelReason reason = StreamingCancelReason.user}) {
    return _executeStreamingQuery.cancelActiveStream(reason: reason);
  }

  void _requestStopAtRowCap(int cap) {
    if (_streamingCapCancelRequested) {
      return;
    }
    _streamingCapCancelRequested = true;
    _streamingStoppedByCap = true;
    unawaited(
      _executeStreamingQuery.cancelActiveStream(
        reason: StreamingCancelReason.playgroundRowCap,
      ),
    );
  }

  void _notifyProgressIfNeeded(PlaygroundStreamingNotifyListener notifyProgress) {
    final now = DateTime.now();
    if (now.difference(_lastNotifyAt) < _uiUpdateInterval) {
      return;
    }
    _lastNotifyAt = now;
    notifyProgress();
  }
}
