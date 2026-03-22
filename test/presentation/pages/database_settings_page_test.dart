import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/database_settings_page.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockConfigProvider extends Mock implements ConfigProvider {}

class MockConnectToHub extends Mock implements ConnectToHub {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockCheckOdbcDriver extends Mock implements CheckOdbcDriver {}

class _FakeConnectionPool implements IConnectionPool {
  @override
  Future<Result<String>> acquire(String connectionString) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> closeAll() async => const Success(unit);

  @override
  Future<Result<int>> getActiveCount() async => const Success(0);

  @override
  Future<Result<void>> healthCheckAll() async => const Success(unit);

  @override
  Future<Result<void>> recycle(String connectionString) async =>
      const Success(unit);

  @override
  Future<Result<void>> release(String connectionId) async =>
      const Success(unit);

  @override
  Future<Result<void>> warmIdleLeases(String connectionString) async =>
      const Success(unit);
}

Future<void> pumpDatabaseSettings(
  WidgetTester tester, {
  required MockConfigProvider mockConfig,
  required ConnectionProvider connectionProvider,
  String? initialTab,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1400));
  await getIt.reset();
  getIt.registerSingleton<IOdbcConnectionSettings>(
    MockOdbcConnectionSettings(),
  );
  getIt.registerSingleton<IConnectionPool>(_FakeConnectionPool());

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
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigProvider>.value(value: mockConfig),
          ChangeNotifierProvider<ConnectionProvider>.value(
            value: connectionProvider,
          ),
        ],
        child: DatabaseSettingsPage(initialTab: initialTab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockConfigProvider mockConfig;
  late MockConnectToHub mockConnect;
  late MockTestDbConnection mockTestDb;
  late MockCheckOdbcDriver mockCheckDriver;
  late ConnectionProvider connectionProvider;

  setUp(() {
    mockConfig = MockConfigProvider();
    mockConnect = MockConnectToHub();
    mockTestDb = MockTestDbConnection();
    mockCheckDriver = MockCheckOdbcDriver();

    when(
      () => mockConnect(any(), any(), authToken: any(named: 'authToken')),
    ).thenAnswer((_) async => const Success(unit));
    when(() => mockTestDb(any())).thenAnswer(
      (_) async => const Success(false),
    );
    when(() => mockCheckDriver(any())).thenAnswer(
      (_) async => const Success(true),
    );

    connectionProvider = ConnectionProvider(
      mockConnect,
      mockTestDb,
      mockCheckDriver,
      configProvider: mockConfig,
    );

    when(() => mockConfig.isLoading).thenReturn(false);
    when(() => mockConfig.currentConfig).thenReturn(null);
    when(() => mockConfig.error).thenReturn('');
    when(() => mockConfig.isPasswordVisible).thenReturn(false);
    when(() => mockConfig.updateDriverName(any())).thenAnswer((_) {});
    when(() => mockConfig.updateOdbcDriverName(any())).thenAnswer((_) {});
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('DatabaseSettingsPage', () {
    testWidgets('should render nav title and database tab content', (
      tester,
    ) async {
      await pumpDatabaseSettings(
        tester,
        mockConfig: mockConfig,
        connectionProvider: connectionProvider,
      );

      expect(find.text('Database'), findsWidgets);
      expect(find.text(AppStrings.dbSectionTitle), findsOneWidget);
      expect(find.text(AppStrings.dbTabDatabase), findsOneWidget);
    });

    testWidgets(
      'should show advanced ODBC pool section when initialTab is advanced',
      (
        tester,
      ) async {
        await pumpDatabaseSettings(
          tester,
          mockConfig: mockConfig,
          connectionProvider: connectionProvider,
          initialTab: 'advanced',
        );

        expect(find.text(AppStrings.odbcSectionTitle), findsOneWidget);
        expect(find.text(AppStrings.odbcFieldPoolSize), findsOneWidget);
      },
    );
  });
}
