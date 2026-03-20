import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';

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
}
