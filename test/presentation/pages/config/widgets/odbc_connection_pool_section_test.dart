import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/odbc_connection_pool_section.dart';
import 'package:result_dart/result_dart.dart';

import '../../../../helpers/mock_odbc_connection_settings.dart';

class _FakeConnectionPool implements IConnectionPool {
  @override
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionOptions? options,
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
      getIt
        ..registerSingleton<IOdbcConnectionSettings>(settings)
        ..registerSingleton<IConnectionPool>(_FakeConnectionPool());

      await tester.pumpWidget(
        FluentApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OdbcConnectionPoolSection(
            reloadOdbcDependencies: () async {
              reloadCount++;
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Native ODBC pool (experimental)'), findsNothing);
      expect(find.text('Validate connection when checking out from native pool'), findsNothing);

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
