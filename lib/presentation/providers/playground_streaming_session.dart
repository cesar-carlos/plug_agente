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
  int _totalRowsFetched = 0;
  DateTime _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get streamingCapCancelRequested => _streamingCapCancelRequested;
  bool get streamingStoppedByCap => _streamingStoppedByCap;

  void resetCapState() {
    _streamingCapCancelRequested = false;
    _streamingStoppedByCap = false;
    _totalRowsFetched = 0;
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
    final remaining = cap - _totalRowsFetched;
    if (remaining <= 0) {
      onRowCapReached(cap);
      _requestStopAtRowCap(cap);
      return;
    }
    final accepted = chunk.length > remaining ? chunk.sublist(0, remaining) : chunk;
    results.addAll(accepted);
    _totalRowsFetched += accepted.length;
    _trimResultsToUiWindow(results);
    onProgress(_totalRowsFetched, progressForRowCount(_totalRowsFetched));
    _notifyProgressIfNeeded(notifyProgress);
    if (_totalRowsFetched >= cap) {
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

  void _trimResultsToUiWindow(List<Map<String, dynamic>> results) {
    final window = ConnectionConstants.playgroundStreamingUiWindowRows;
    if (window < 1 || results.length <= window) {
      return;
    }
    final overflow = results.length - window;
    results.removeRange(0, overflow);
  }
}
