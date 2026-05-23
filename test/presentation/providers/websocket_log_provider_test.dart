import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:result_dart/result_dart.dart';

class _RecordingTransport implements ITransportClient {
  void Function(String, String, dynamic)? messageCallback;

  @override
  Future<Result<void>> connect(String url, String agentId, {String? authToken}) async => const Success(unit);

  @override
  Future<Result<void>> disconnect() async => const Success(unit);

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async => const Success(unit);

  @override
  bool get isConnected => false;

  @override
  String get agentId => 'agent-test';

  @override
  void setMessageCallback(void Function(String, String, dynamic)? callback) => messageCallback = callback;

  @override
  void setOnTokenExpired(void Function()? callback) {}

  @override
  void setOnReconnectionNeeded(void Function()? callback) {}

  @override
  void setOnHubLifecycle(void Function(HubLifecycleNotification)? callback) {}

  @override
  void setResilienceLogContext(String? recoveryId) {}
}

void main() {
  group('WebSocketMessage', () {
    test('should compute formattedData once and include JSON for map data', () {
      final message = WebSocketMessage(
        timestamp: DateTime.utc(2026),
        direction: 'IN',
        event: 'rpc:request',
        data: {'id': 1, 'method': 'test'},
      );

      expect(message.formattedData, contains('id'));
      expect(message.formattedData, contains('test'));
      expect(message.displayText, contains('IN'));
      expect(message.displayText, contains('rpc:request'));
    });

    test('should truncate large formatted payload', () {
      final large = List.filled(9000, 'a').join();
      final message = WebSocketMessage(
        timestamp: DateTime.utc(2026),
        direction: 'IN',
        event: 'big',
        data: large,
      );

      expect(message.formattedData.length, lessThan(8500));
      expect(message.formattedData, contains('[truncated'));
    });
  });

  group('WebSocketLogProvider', () {
    test('should forward transport messages when logging is enabled', () {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      transport.messageCallback?.call('OUT', 'rpc:response', {'ok': true});

      expect(provider.messages, hasLength(1));
      expect(provider.messages.first.direction, 'OUT');
      expect(provider.messages.first.event, 'rpc:response');
    });

    test('should ignore transport messages when logging is disabled', () {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport)..setEnabled(false);

      transport.messageCallback?.call('IN', 'ping', null);

      expect(provider.messages, isEmpty);
    });
  });
}
