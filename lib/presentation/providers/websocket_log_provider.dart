import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';

const _maxMessagesDefault = 500;

/// Max chars for formattedData before truncation to avoid heavy UI work.
const _maxFormattedDataChars = 8000;

String _computeFormattedData(dynamic data) {
  try {
    String raw;
    if (data is Map || data is List) {
      final compact = jsonEncode(data);
      raw = compact.length > _maxFormattedDataChars ? compact : const JsonEncoder.withIndent('  ').convert(data);
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

class WebSocketMessage {
  WebSocketMessage({
    required this.timestamp,
    required this.direction,
    required this.event,
    required this.data,
  }) : formattedData = _computeFormattedData(data);

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
    Duration debounceDelay = const Duration(milliseconds: 80),
  }) : _debounceDelay = debounceDelay;

  final List<WebSocketMessage> _messages = [];
  bool _isEnabled = true;
  int _maxMessages = _maxMessagesDefault;
  final Duration _debounceDelay;
  Timer? _notifyDebounceTimer;

  List<WebSocketMessage> get messages => List.unmodifiable(_messages);
  bool get isEnabled => _isEnabled;
  int get maxMessages => _maxMessages;

  void addMessage(String direction, String event, dynamic data) {
    if (!_isEnabled) return;

    final sanitizedData = LogSanitizer.sanitize(data);
    final message = WebSocketMessage(
      timestamp: DateTime.now(),
      direction: direction,
      event: event,
      data: sanitizedData,
    );

    _messages.insert(0, message);

    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }

    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(_debounceDelay, () {
      _notifyDebounceTimer = null;
      notifyListeners();
    });
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    notifyListeners();
  }

  void setMaxMessages(int max) {
    _maxMessages = max;
    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = null;
    super.dispose();
  }
}
