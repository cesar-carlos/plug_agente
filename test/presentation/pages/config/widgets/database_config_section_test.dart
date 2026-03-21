import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/database_config_section.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConfigProvider extends Mock implements ConfigProvider {}

class MockConnectToHub extends Mock implements ConnectToHub {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockCheckOdbcDriver extends Mock implements CheckOdbcDriver {}

void main() {
  group('DatabaseConfigSection', () {
    late ConfigFormController formController;
    late MockConfigProvider mockConfig;
    late MockConnectToHub mockConnect;
    late MockTestDbConnection mockTestDb;
    late MockCheckOdbcDriver mockCheckDriver;
    late ConnectionProvider connectionProvider;

    setUp(() {
      formController = ConfigFormController();
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
    });

    testWidgets('should render database section title and driver field', (
      tester,
    ) async {
      formController.driverNameController.text =
          DatabaseDriver.sqlServer.displayName;
      formController.odbcDriverNameController.text = 'ODBC Driver 17';
      formController.hostController.text = 'localhost';
      formController.portController.text = '1433';

      await tester.binding.setSurfaceSize(const Size(1600, 1400));
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
            child: ScaffoldPage(
              content: DatabaseConfigSection(
                formController: formController,
                configProvider: mockConfig,
                connectionProvider: connectionProvider,
                onDriverChanged: (_) {},
                onTestConnection: () async {},
                onSaveConfig: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.dbSectionTitle), findsOneWidget);
      expect(find.text(AppStrings.dbFieldDatabaseDriver), findsOneWidget);
      expect(find.text(AppStrings.dbFieldOdbcDriverName), findsOneWidget);
      expect(find.text(AppStrings.dbButtonTestConnection), findsOneWidget);
      expect(find.text(AppStrings.wsButtonSaveConfig), findsOneWidget);
    });

    testWidgets(
      'should invoke onTestConnection when required fields are filled',
      (tester) async {
        var testCalls = 0;
        formController.driverNameController.text =
            DatabaseDriver.sqlServer.displayName;
        formController.odbcDriverNameController.text = 'ODBC Driver 17';
        formController.hostController.text = '127.0.0.1';
        formController.portController.text = '1433';

        await tester.binding.setSurfaceSize(const Size(1600, 1400));
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
              child: ScaffoldPage(
                content: DatabaseConfigSection(
                  formController: formController,
                  configProvider: mockConfig,
                  connectionProvider: connectionProvider,
                  onDriverChanged: (_) {},
                  onTestConnection: () async {
                    testCalls++;
                  },
                  onSaveConfig: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.dbButtonTestConnection));
        await tester.pumpAndSettle();

        expect(testCalls, 1);
      },
    );
  });
}
