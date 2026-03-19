import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConnectToHub extends Mock implements ConnectToHub {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockCheckOdbcDriver extends Mock implements CheckOdbcDriver {}

class MockConfigProvider extends Mock implements ConfigProvider {}

class FakeTransportClient implements ITransportClient {
  void Function()? onTokenExpired;
  void Function()? onReconnectionNeeded;

  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> disconnect() async => const Success(unit);

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async => const Success(unit);

  @override
  bool get isConnected => false;

  @override
  String get agentId => '';

  @override
  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  ) {}

  @override
  void setOnTokenExpired(void Function()? callback) {
    onTokenExpired = callback;
  }

  @override
  void setOnReconnectionNeeded(void Function()? callback) {
    onReconnectionNeeded = callback;
  }

  void triggerReconnectionNeeded() => onReconnectionNeeded?.call();
  // ignore: unreachable_from_main - used by tests that verify token expiry flow
  void triggerTokenExpired() => onTokenExpired?.call();
}

Future<void> waitForStatus(
  ConnectionProvider provider,
  ConnectionStatus expected, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (provider.status == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Expected status $expected within ${timeout.inMilliseconds}ms, '
    'but got ${provider.status}',
  );
}

void main() {
  group('ConnectionRecoveryIntegration', () {
    late MockConnectToHub mockConnectToHub;
    late MockTestDbConnection mockTestDb;
    late MockCheckOdbcDriver mockCheckDriver;
    late MockConfigProvider mockConfigProvider;
    late FakeTransportClient fakeTransport;

    setUp(() {
      mockConnectToHub = MockConnectToHub();
      mockTestDb = MockTestDbConnection();
      mockCheckDriver = MockCheckOdbcDriver();
      mockConfigProvider = MockConfigProvider();
      fakeTransport = FakeTransportClient();
    });

    test('should recover connection after failures with backoff', () async {
      var connectCallCount = 0;
      when(
        () => mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
      ).thenAnswer((_) async {
        connectCallCount++;
        if (connectCallCount == 1) {
          return const Success(unit);
        }
        if (connectCallCount <= 3) {
          return Failure(Exception('Reconnect failed'));
        }
        return const Success(unit);
      });

      when(() => mockConfigProvider.currentConfig).thenReturn(null);

      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
        initialReconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        maxReconnectAttempts: 6,
      );

      await provider.connect('https://hub.test', 'agent-1');
      expect(provider.status, ConnectionStatus.connected);

      fakeTransport.triggerReconnectionNeeded();

      await waitForStatus(provider, ConnectionStatus.reconnecting);
      await waitForStatus(provider, ConnectionStatus.connected);
      verify(
        () => mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
      ).called(greaterThanOrEqualTo(4));
    });

    test('should fail recovery when all retries exhausted', () async {
      var connectCallCount = 0;
      when(
        () => mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
      ).thenAnswer((_) async {
        connectCallCount++;
        if (connectCallCount == 1) {
          return const Success(unit);
        }
        return Failure(Exception('Reconnect always fails'));
      });

      when(() => mockConfigProvider.currentConfig).thenReturn(null);

      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
        initialReconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
      );

      await provider.connect('https://hub.test', 'agent-1');
      expect(provider.status, ConnectionStatus.connected);

      fakeTransport.triggerReconnectionNeeded();

      await waitForStatus(provider, ConnectionStatus.error);
      expect(provider.status, ConnectionStatus.error);
      expect(provider.error, contains('Failed to recover'));
    });
  });
}
