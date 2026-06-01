import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';
import 'package:plug_agente/core/utils/sql_rpc_log_payload_compactor.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

const int _maxMessagesDefault = AppConstants.dashboardDiagnosticFeedMaxItems;
const int _maxPendingMessages = AppConstants.dashboardDiagnosticFeedMaxItems;

/// Max chars for formattedData before truncation to avoid heavy UI work.
const _maxFormattedDataChars = 8000;

const Duration _logBatchFlushDelay = Duration(milliseconds: 50);

bool _preferCompactFormat(String event) {
  return event.startsWith('rpc:') || event.startsWith('agent:') || event == 'hub:heartbeat_ack';
}

/// Lightweight dashboard text for high-frequency hub sql.execute socket events.
/// Avoids walking/encoding full row payloads in [LogSanitizer] and [jsonEncode].
String? _dashboardFormattedPreview(String event, dynamic data) {
  if (data is! Map) {
    return null;
  }
  switch (event) {
    case 'rpc:chunk':
      final rows = data['rows'];
      final rowCount = rows is List ? rows.length : 0;
      return 'chunk_index=${data['chunk_index']} rows=$rowCount '
          '(row payload omitted from dashboard feed)';
    case 'rpc:complete':
      return 'stream_id=${data['stream_id']} total_rows=${data['total_rows']}'
          '${data['terminal_status'] != null ? ' terminal_status=${data['terminal_status']}' : ''}';
    case 'rpc:response':
      return SqlRpcLogPayloadCompactor.rpcResponsePreview(data);
    case 'rpc:request':
      final method = data['method'];
      if (method != 'sql.execute') {
        return null;
      }
      final params = data['params'];
      if (params is! Map) {
        return null;
      }
      final sql = params['sql'];
      if (sql is! String) {
        return null;
      }
      final clipped = sql.length > 160 ? '${sql.substring(0, 160)}...' : sql;
      return 'method=$method id=${data['id']}\nsql: $clipped';
    default:
      return null;
  }
}

Map<String, dynamic> _dashboardDataSnapshot(String event, dynamic data) {
  return SqlRpcLogPayloadCompactor.dashboardDataSnapshot(event, data);
}

String _computeFormattedData(dynamic data, {required String event}) {
  try {
    String raw;
    if (data is Map || data is List) {
      final compact = jsonEncode(data);
      raw = _preferCompactFormat(event) || compact.length > _maxFormattedDataChars
          ? compact
          : const JsonEncoder.withIndent('  ').convert(data);
    } else {
      raw = data.toString();
    }
    if (raw.length > _maxFormattedDataChars) {
      return '${raw.substring(0, _maxFormattedDataChars)}\n'
          '... [truncated, ${raw.length} chars]';
    }
    return raw;
  } on Exception catch (e, stackTrace) {
    developer.log(
      'WebSocket message format failed',
      name: 'websocket_log_provider',
      level: 700,
      error: e,
      stackTrace: stackTrace,
    );
    return '[Unable to format]';
  }
}

class _PendingLogEntry {
  const _PendingLogEntry({
    required this.direction,
    required this.event,
    required this.data,
    this.formattedPreview,
  });

  final String direction;
  final String event;
  final dynamic data;
  final String? formattedPreview;
}

class WebSocketMessage {
  WebSocketMessage({
    required this.timestamp,
    required this.direction,
    required this.event,
    required this.data,
    String? formattedPreview,
  }) : formattedData = formattedPreview ?? _computeFormattedData(data, event: event);

  final DateTime timestamp;
  final String direction;
  final String event;
  final dynamic data;

  /// Precomputed once at construction so ListView rebuilds do not re-run JSON encode.
  final String formattedData;

  String get displayText {
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    return '[$time] $direction: $event\n$formattedData';
  }
}

class WebSocketLogProvider extends ChangeNotifier {
  WebSocketLogProvider({
    ITransportClient? transportClient,
    Duration debounceDelay = const Duration(milliseconds: 80),
  }) : _debounceDelay = debounceDelay {
    if (transportClient != null) {
      attachTransport(transportClient);
    }
  }

  final List<WebSocketMessage> _messages = [];
  final ListQueue<_PendingLogEntry> _pending = ListQueue<_PendingLogEntry>();
  bool _isEnabled = true;
  bool _hubSqlCapturePaused = false;
  bool _isDisposed = false;
  int _pendingDrops = 0;
  int _pendingFlushGeneration = 0;
  int _maxMessages = _maxMessagesDefault;
  final Duration _debounceDelay;
  Timer? _notifyDebounceTimer;
  Timer? _batchFlushTimer;

  List<WebSocketMessage> get messages => List.unmodifiable(_messages);
  bool get isEnabled => _isEnabled;
  int get maxMessages => _maxMessages;

  void attachTransport(ITransportClient transportClient) {
    transportClient.setMessageCallback((String direction, String event, dynamic data) {
      if (_isEnabled && !_isDisposed) {
        addMessage(direction, event, data);
      }
    });
    transportClient.setHubSqlDashboardCapturePauseHandler(_setHubSqlCapturePaused);
  }

  /// While hub sql.execute runs, queue socket feed updates and skip UI notify.
  void pauseForHubSqlCapture() {
    if (_isDisposed) {
      return;
    }
    if (_hubSqlCapturePaused) {
      return;
    }
    _hubSqlCapturePaused = true;
    _pendingFlushGeneration++;
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = null;
    _batchFlushTimer?.cancel();
    _batchFlushTimer = null;
  }

  /// Flushes messages collected during [pauseForHubSqlCapture] in one batch.
  void resumeAfterHubSqlCapture() {
    if (_isDisposed) {
      return;
    }
    if (!_hubSqlCapturePaused) {
      return;
    }
    _hubSqlCapturePaused = false;
    _pendingFlushGeneration++;
    if (_pending.isEmpty && _pendingDrops == 0) {
      return;
    }
    final generation = _pendingFlushGeneration;
    scheduleMicrotask(() {
      if (_isDisposed || _hubSqlCapturePaused || !_isEnabled || generation != _pendingFlushGeneration) {
        return;
      }
      _batchFlushTimer?.cancel();
      _batchFlushTimer = null;
      _flushPendingMessages();
    });
  }

  void _setHubSqlCapturePaused(bool paused) {
    if (paused) {
      pauseForHubSqlCapture();
    } else {
      resumeAfterHubSqlCapture();
    }
  }

  void addMessage(String direction, String event, dynamic data) {
    if (!_isEnabled || _isDisposed) {
      return;
    }
    final preview = _dashboardFormattedPreview(event, data);
    _enqueuePending(
      _PendingLogEntry(
        direction: direction,
        event: event,
        data: preview == null ? data : _dashboardDataSnapshot(event, data),
        formattedPreview: preview,
      ),
    );
    if (_hubSqlCapturePaused) {
      return;
    }
    _batchFlushTimer ??= Timer(_logBatchFlushDelay, _flushPendingMessages);
  }

  void _enqueuePending(_PendingLogEntry entry) {
    _pending.addLast(entry);
    while (_pending.length > _maxPendingMessages) {
      _pending.removeFirst();
      _pendingDrops++;
    }
  }

  void _flushPendingMessages() {
    _batchFlushTimer = null;
    if (_isDisposed || !_isEnabled || _hubSqlCapturePaused || (_pending.isEmpty && _pendingDrops == 0)) {
      return;
    }
    final generation = _pendingFlushGeneration;
    scheduleMicrotask(() => _processPendingBatch(generation));
  }

  void _processPendingBatch(int generation) {
    if (_isDisposed || !_isEnabled || _hubSqlCapturePaused || generation != _pendingFlushGeneration) {
      return;
    }
    if (_pending.isEmpty && _pendingDrops == 0) {
      return;
    }

    final batch = List<_PendingLogEntry>.from(_pending);
    _pending.clear();
    final dropped = _pendingDrops;
    _pendingDrops = 0;
    if (dropped > 0) {
      batch.add(
        _PendingLogEntry(
          direction: 'SYSTEM',
          event: 'dashboard:pending_overflow',
          data: <String, dynamic>{
            'dropped': dropped,
            'pending_cap': _maxPendingMessages,
          },
          formattedPreview: 'Dropped $dropped pending dashboard logs while capture was paused',
        ),
      );
    }

    for (final entry in batch) {
      final preview = entry.formattedPreview;
      final sanitizedData = preview == null ? LogSanitizer.sanitize(entry.data) : entry.data;
      _messages.insert(
        0,
        WebSocketMessage(
          timestamp: DateTime.now(),
          direction: entry.direction,
          event: entry.event,
          data: sanitizedData,
          formattedPreview: preview,
        ),
      );
    }

    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }

    if (_hubSqlCapturePaused || generation != _pendingFlushGeneration) {
      return;
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_isDisposed) {
      return;
    }
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(_debounceDelay, () {
      if (_isDisposed) {
        return;
      }
      _notifyDebounceTimer = null;
      notifyListeners();
    });
  }

  void clearMessages() {
    if (_isDisposed) {
      return;
    }
    _pending.clear();
    _pendingDrops = 0;
    _pendingFlushGeneration++;
    _batchFlushTimer?.cancel();
    _batchFlushTimer = null;
    _messages.clear();
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    if (_isDisposed) {
      return;
    }
    _isEnabled = enabled;
    if (!enabled) {
      _hubSqlCapturePaused = false;
      _pending.clear();
      _pendingDrops = 0;
      _pendingFlushGeneration++;
      _batchFlushTimer?.cancel();
      _batchFlushTimer = null;
    }
    notifyListeners();
  }

  void setMaxMessages(int max) {
    if (_isDisposed) {
      return;
    }
    _maxMessages = max;
    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pending.clear();
    _pendingDrops = 0;
    _pendingFlushGeneration++;
    _batchFlushTimer?.cancel();
    _batchFlushTimer = null;
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = null;
    super.dispose();
  }
}
