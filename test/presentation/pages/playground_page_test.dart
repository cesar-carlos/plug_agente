import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/playground_page.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockExecutePlaygroundQuery extends Mock
    implements ExecutePlaygroundQuery {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockExecuteStreamingQuery extends Mock implements ExecuteStreamingQuery {}

class MockConfigProvider extends Mock implements ConfigProvider {}

class _FakeAppSettingsStore implements IAppSettingsStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set<String> getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  List<String>? getStringList(String key) => _values[key] as List<String>?;

  @override
  Object? getValue(String key) => _values[key];

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _values[key] = value;
  }

  @override
  Future<void> setValue(String key, Object value) async {
    _values[key] = value;
  }

  @override
  Future<void> setValues(Map<String, Object> values) async {
    _values.addAll(values);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAppSettingsStore appSettingsStore;

  setUpAll(() {
    registerFallbackValue(
      const QueryPaginationRequest(page: 1, pageSize: 50),
    );
  });

  setUp(() {
    appSettingsStore = _FakeAppSettingsStore();
  });

  group('PlaygroundPage', () {
    late MockExecutePlaygroundQuery mockExecute;
    late MockTestDbConnection mockTestDb;
    late MockExecuteStreamingQuery mockStream;
    late PlaygroundProvider playgroundProvider;
    late MockConfigProvider mockConfig;
    late Config sampleConfig;

    tearDown(() async {
      await getIt.reset();
    });

    setUp(() {
      mockExecute = MockExecutePlaygroundQuery();
      mockTestDb = MockTestDbConnection();
      mockStream = MockExecuteStreamingQuery();
      playgroundProvider = PlaygroundProvider(
        mockExecute,
        mockTestDb,
        mockStream,
      );
      mockConfig = MockConfigProvider();

      final now = DateTime.utc(2026);
      sampleConfig = Config(
        id: 'c1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17',
        connectionString: 'DSN=TestDb',
        username: 'u',
        databaseName: 'db',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );

      when(() => mockConfig.currentConfig).thenReturn(sampleConfig);
      when(() => mockConfig.isLoading).thenReturn(false);
      when(() => mockConfig.error).thenReturn('');
      when(() => mockConfig.isPasswordVisible).thenReturn(false);
    });

    Future<void> pumpPlayground(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await getIt.reset();
      getIt.registerSingleton<IAppSettingsStore>(appSettingsStore);
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
              ChangeNotifierProvider<PlaygroundProvider>.value(
                value: playgroundProvider,
              ),
              ChangeNotifierProvider<ConfigProvider>.value(
                value: mockConfig,
              ),
            ],
            child: const PlaygroundPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('should render playground title', (tester) async {
      await pumpPlayground(tester);
      expect(find.text('Playground Database'), findsOneWidget);
    });

    testWidgets('should run execute when tapping run query', (tester) async {
      when(
        () => mockExecute(any(), pagination: any(named: 'pagination')),
      ).thenAnswer(
        (_) async => Success(
          QueryResponse(
            id: 'r1',
            requestId: 'q1',
            agentId: 'a1',
            data: const [
              {'id': 1},
            ],
            timestamp: DateTime.now(),
          ),
        ),
      );

      await pumpPlayground(tester);

      await tester.enterText(
        find.byType(TextBox).first,
        'SELECT 1',
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();

      verify(
        () => mockExecute(any(), pagination: any(named: 'pagination')),
      ).called(1);
      expect(playgroundProvider.results, hasLength(1));
    });

    testWidgets('should persist streaming toggle to settings store', (
      tester,
    ) async {
      await pumpPlayground(tester);

      final streamingLabel = find.text('Streaming mode');
      expect(streamingLabel, findsOneWidget);
      final streamingToggle = find.ancestor(
        of: streamingLabel,
        matching: find.byType(ToggleSwitch),
      );
      await tester.tap(streamingToggle);
      await tester.pumpAndSettle();

      expect(
        appSettingsStore.getBool('playground_streaming_mode_enabled'),
        isTrue,
      );
    });
  });
}
