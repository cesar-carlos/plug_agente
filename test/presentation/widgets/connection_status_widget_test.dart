import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConnectToHub extends Mock implements ConnectToHub {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockCheckOdbcDriver extends Mock implements CheckOdbcDriver {}

class MockConfigProvider extends Mock implements ConfigProvider {}

class _FakeTransportClient implements ITransportClient {
  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async => const Success(unit);

  @override
  Future<Result<void>> disconnect() async => const Success(unit);

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async =>
      const Success(unit);

  @override
  bool get isConnected => false;

  @override
  String get agentId => '';

  @override
  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  ) {}

  @override
  void setOnTokenExpired(void Function()? callback) {}

  @override
  void setOnReconnectionNeeded(void Function()? callback) {}
}

void main() {
  late MockConnectToHub mockConnectToHub;
  late MockTestDbConnection mockTestDb;
  late MockCheckOdbcDriver mockCheckDriver;
  late MockConfigProvider mockConfigProvider;
  late _FakeTransportClient fakeTransport;

  setUp(() {
    mockConnectToHub = MockConnectToHub();
    mockTestDb = MockTestDbConnection();
    mockCheckDriver = MockCheckOdbcDriver();
    mockConfigProvider = MockConfigProvider();
    fakeTransport = _FakeTransportClient();

    when(
      () => mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
    ).thenAnswer((_) async => const Success(unit));
    when(() => mockConfigProvider.currentConfig).thenReturn(null);
  });

  Future<void> pumpStatus(
    WidgetTester tester,
    ConnectionProvider connectionProvider,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 200));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FluentLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ConnectionProvider>.value(
          value: connectionProvider,
          child: const ScaffoldPage(
            content: ConnectionStatusWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ConnectionStatusWidget', () {
    testWidgets('should show disconnected labels by default', (tester) async {
      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
      );

      await pumpStatus(tester, provider);

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('DB: disconnected'), findsOneWidget);
    });

    testWidgets('should show connecting while hub connect is pending', (
      tester,
    ) async {
      final completer = Completer<Result<void>>();
      when(
        () =>
            mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
      ).thenAnswer((_) => completer.future);

      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
      );

      final connectFuture = provider.connect('https://hub.test', 'agent-1');
      await pumpStatus(tester, provider);

      expect(find.text('Connecting...'), findsOneWidget);

      completer.complete(const Success(unit));
      await connectFuture;
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('should show error when connect fails', (tester) async {
      when(
        () =>
            mockConnectToHub(any(), any(), authToken: any(named: 'authToken')),
      ).thenAnswer(
        (_) async => Failure(Exception('hub unavailable')),
      );

      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
      );

      await provider.connect('https://hub.test', 'agent-1');
      await pumpStatus(tester, provider);

      expect(find.text('Connection error'), findsOneWidget);
    });

    testWidgets('should show DB connected after successful testDbConnection', (
      tester,
    ) async {
      when(
        () => mockTestDb(any()),
      ).thenAnswer((_) async => const Success(true));

      final provider = ConnectionProvider(
        mockConnectToHub,
        mockTestDb,
        mockCheckDriver,
        configProvider: mockConfigProvider,
        transportClient: fakeTransport,
      );

      await provider.testDbConnection('DSN=Test');
      await pumpStatus(tester, provider);

      expect(find.text('DB: connected'), findsOneWidget);
    });
  });
}
