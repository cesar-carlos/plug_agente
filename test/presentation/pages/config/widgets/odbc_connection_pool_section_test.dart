import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/reload_odbc_runtime_dependencies.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_runtime_reloader.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/odbc_connection_pool_section.dart';
import 'package:result_dart/result_dart.dart';

import '../../../../helpers/mock_odbc_connection_settings.dart';

class _FakeConnectionPool implements IConnectionPool, IConnectionPoolDiagnostics {
  @override
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionAcquireOptions? options,
  }) async {
    return const Success('connection-id');
  }

  @override
  Future<Result<void>> closeAll() async => const Success(unit);

  @override
  Future<Result<void>> discard(String connectionId) async => const Success(unit);

  @override
  Future<Result<int>> getActiveCount({String? connectionString}) async => const Success(0);

  @override
  Future<Result<void>> healthCheckAll() async => const Success(unit);

  @override
  Future<Result<void>> recycle(String connectionString) async => const Success(unit);

  @override
  Future<Result<void>> release(String connectionId) async => const Success(unit);

  @override
  Map<String, Object?> getHealthDiagnostics() {
    return {
      'strategy': 'adaptive_experimental',
      'effective_strategy': 'native',
      'experimental_enabled': true,
      'native_eligible': true,
      'native_circuit_open': false,
      'native_skip_reason': null,
    };
  }
}

class _RecordingOdbcRuntimeReloader implements IOdbcRuntimeReloader {
  _RecordingOdbcRuntimeReloader(this._reload);

  final Future<bool> Function() _reload;

  @override
  Future<bool> reload() => _reload();
}

void main() {
  group('OdbcConnectionPoolSection', () {
    setUp(() async {
      await getIt.reset();
    });

    tearDown(() async {
      await getIt.reset();
    });

    testWidgets('should hide native pool toggles and save advanced ODBC settings', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var reloadCount = 0;
      final settings = MockOdbcConnectionSettings(
        poolSize: 3,
        useNativeOdbcPool: true,
        nativePoolTestOnCheckout: false,
      );
      final reloadOdbcRuntime = ReloadOdbcRuntimeDependencies(
        _RecordingOdbcRuntimeReloader(() async {
          reloadCount++;
          return true;
        }),
      );
      getIt
        ..registerSingleton<IOdbcConnectionSettings>(settings)
        ..registerSingleton<IConnectionPool>(_FakeConnectionPool())
        ..registerSingleton<ReloadOdbcRuntimeDependencies>(reloadOdbcRuntime);

      await tester.pumpWidget(
        const FluentApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OdbcConnectionPoolSection(),
        ),
      );
      await tester.pump();

      expect(find.text('Native ODBC pool (experimental)'), findsNothing);
      expect(find.text('Validate connection when checking out from native pool'), findsNothing);
      expect(find.textContaining('DirectOdbcConnectionLimiter'), findsOneWidget);
      expect(find.textContaining('Effective strategy: native'), findsOneWidget);
      expect(find.textContaining('Adaptive experimental pooling: enabled'), findsOneWidget);

      final fields = find.byType(TextBox);
      expect(fields, findsNWidgets(4));
      await tester.enterText(fields.at(0), '6');
      await tester.enterText(fields.at(1), '45');
      await tester.enterText(fields.at(2), '96');
      await tester.enterText(fields.at(3), '2048');

      final saveButton = find.text('Save advanced settings');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(reloadCount, 1);
      expect(settings.poolSize, 6);
      expect(settings.loginTimeoutSeconds, 45);
      expect(settings.maxResultBufferMb, 96);
      expect(settings.streamingChunkSizeKb, 2048);
      expect(settings.useNativeOdbcPool, isTrue);
      expect(settings.nativePoolTestOnCheckout, isFalse);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
