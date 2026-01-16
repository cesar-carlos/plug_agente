import 'package:flutter/foundation.dart';
import 'dart:convert';

class WebSocketMessage {
  final DateTime timestamp;
  final String direction;
  final String event;
  final dynamic data;

  WebSocketMessage({
    required this.timestamp,
    required this.direction,
    required this.event,
    required this.data,
  });

  String get formattedData {
    try {
      if (data is Map || data is List) {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
      return data.toString();
    } catch (e) {
      return data.toString();
    }
  }

  String get displayText {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    return '[$time] $direction: $event\n$formattedData';
  }
}

class WebSocketLogProvider extends ChangeNotifier {
  final List<WebSocketMessage> _messages = [];
  bool _isEnabled = true;
  int _maxMessages = 500;

  List<WebSocketMessage> get messages => List.unmodifiable(_messages);
  bool get isEnabled => _isEnabled;
  int get maxMessages => _maxMessages;

  void addMessage(String direction, String event, dynamic data) {
    if (!_isEnabled) return;

    final message = WebSocketMessage(
      timestamp: DateTime.now(),
      direction: direction,
      event: event,
      data: data,
    );

    _messages.insert(0, message);

    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }

    notifyListeners();
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
}
