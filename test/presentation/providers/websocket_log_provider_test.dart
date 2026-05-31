import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
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
  void setHubSqlDashboardCapturePauseHandler(void Function(bool paused)? handler) {}

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
  TestWidgetsFlutterBinding.ensureInitialized();

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
    test('should forward transport messages when logging is enabled', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      transport.messageCallback?.call('OUT', 'rpc:response', {'ok': true});
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(provider.messages, hasLength(1));
      expect(provider.messages.first.direction, 'OUT');
      expect(provider.messages.first.event, 'rpc:response');
    });

    test('should defer flush while hub sql capture is paused', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      provider.pauseForHubSqlCapture();
      transport.messageCallback?.call('SENT', 'rpc:chunk', <String, dynamic>{
        'chunk_index': 0,
        'rows': <Map<String, dynamic>>[],
      });
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(provider.messages, isEmpty);

      provider.resumeAfterHubSqlCapture();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(provider.messages, hasLength(1));
    });

    test('should flush once after rapid pause/resume toggles', () {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      fakeAsync((async) {
        provider.pauseForHubSqlCapture();
        transport.messageCallback?.call('RECEIVED', 'rpc:request', {'id': '1'});

        provider.resumeAfterHubSqlCapture();
        provider.pauseForHubSqlCapture();
        provider.resumeAfterHubSqlCapture();
        async.flushMicrotasks();
        expect(provider.messages, hasLength(1));
      });
    });

    test('should batch hub sql socket events into one flush', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      transport.messageCallback?.call('RECEIVED', 'rpc:request', {
        'id': '1',
        'method': 'sql.execute',
        'params': {'sql': 'SELECT 1'},
      });
      transport.messageCallback?.call('SENT', 'rpc:chunk', {
        'chunk_index': 0,
        'rows': [
          {'CodCliente': 'x'},
        ],
      });
      transport.messageCallback?.call('SENT', 'rpc:response', <String, dynamic>{'result': <String, dynamic>{}});

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(provider.messages, hasLength(3));
      final chunkMessage = provider.messages.firstWhere((m) => m.event == 'rpc:chunk');
      expect(chunkMessage.formattedData, contains('rows=1'));
      expect(
        chunkMessage.formattedData,
        isNot(contains('CodCliente')),
      );
      expect(chunkMessage.data, containsPair('rows', 'omitted'));
      expect(chunkMessage.data.toString(), isNot(contains('CodCliente')));
    });

    test('should not retain raw chunk rows while hub sql capture is paused', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      provider.pauseForHubSqlCapture();
      transport.messageCallback?.call('SENT', 'rpc:chunk', {
        'chunk_index': 0,
        'rows': [
          {'large_secret_value': 'raw-row-should-not-be-retained'},
        ],
      });

      provider.resumeAfterHubSqlCapture();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final chunkMessage = provider.messages.single;
      expect(chunkMessage.formattedData, contains('rows=1'));
      expect(chunkMessage.data.toString(), isNot(contains('raw-row-should-not-be-retained')));
    });

    test('should cap paused pending queue and publish synthetic overflow summary', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport)..setMaxMessages(2000);
      const totalMessages = AppConstants.dashboardDiagnosticFeedMaxItems + 25;
      const dropped = totalMessages - AppConstants.dashboardDiagnosticFeedMaxItems;

      provider.pauseForHubSqlCapture();
      for (var index = 0; index < totalMessages; index++) {
        transport.messageCallback?.call('RECEIVED', 'test:event', {'seq': index});
      }

      provider.resumeAfterHubSqlCapture();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(provider.messages.length, AppConstants.dashboardDiagnosticFeedMaxItems + 1);
      final overflowMessage = provider.messages.firstWhere((message) => message.event == 'dashboard:pending_overflow');
      expect(overflowMessage.formattedData, contains('Dropped $dropped pending dashboard logs'));
      expect(overflowMessage.data, containsPair('dropped', dropped));
      expect(
        overflowMessage.data,
        containsPair('pending_cap', AppConstants.dashboardDiagnosticFeedMaxItems),
      );

      final seqValues = provider.messages
          .where((message) => message.data is Map && (message.data as Map).containsKey('seq'))
          .map((message) => ((message.data as Map)['seq'] as num).toInt())
          .toList();
      expect(seqValues, isNotEmpty);
      expect(seqValues.every((value) => value >= dropped), isTrue);
      expect(seqValues.contains(dropped - 1), isFalse);
    });

    test('should ignore pending microtasks after dispose', () async {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport);

      transport.messageCallback?.call('SENT', 'rpc:chunk', {
        'chunk_index': 0,
        'rows': [
          {'value': 'ignored'},
        ],
      });
      provider.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(provider.messages, isEmpty);
    });

    test('should ignore transport messages when logging is disabled', () {
      final transport = _RecordingTransport();
      final provider = WebSocketLogProvider(transportClient: transport)..setEnabled(false);

      transport.messageCallback?.call('IN', 'ping', null);

      expect(provider.messages, isEmpty);
    });
  });
}
