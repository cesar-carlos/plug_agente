import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class FakeAutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  FakeAutoUpdateOrchestrator({
    required this.isAvailable,
    this.onCheckManual,
    this.lastManualDiagnostics,
  });

  @override
  final bool isAvailable;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  Future<Result<bool>> Function()? onCheckManual;

  @override
  Future<Result<bool>> checkManual() async {
    if (onCheckManual != null) {
      return onCheckManual!.call();
    }
    return const Success(false);
  }

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<void> initialize() async {}
}

void main() {
  late AppLocalizations ptL10n;
  late InMemoryAppSettingsStore settingsStore;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  setUp(() async {
    settingsStore = InMemoryAppSettingsStore();
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required FakeAutoUpdateOrchestrator orchestrator,
  }) async {
    getIt.registerSingleton<RuntimeCapabilities>(RuntimeCapabilities.full());
    getIt.registerSingleton<IAutoUpdateOrchestrator>(orchestrator);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(settingsStore),
          ),
          ChangeNotifierProvider<SystemSettingsProvider>(
            create: (_) => SystemSettingsProvider(settingsStore),
          ),
        ],
        child: const FluentApp(
          locale: Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NavigationView(
            content: ConfigPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows spinner only while manual update future is pending', (tester) async {
    final completer = Completer<Result<bool>>();
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onCheckManual: () => completer.future,
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.byKey(const ValueKey('updates_refresh_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('updates_refresh_button')), findsNothing);

    completer.complete(const Success(false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
    expect(find.byKey(const ValueKey('updates_refresh_button')), findsOneWidget);
  });

  testWidgets('shows failure technical details when manual check fails', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastManualDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 4, 10, 30),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml?cb=1',
        currentVersion: '1.5.2+1',
        probeRequestUrl: 'https://example.com/appcast.xml?cb=1',
        completedAt: DateTime(2026, 5, 4, 10, 31),
        completionSource: UpdateCheckCompletionSource.completionTimeout,
        probeSucceeded: true,
        appcastProbeVersion: '1.5.3+1',
        errorMessage: 'Update check timed out while waiting for updater completion',
      ),
      onCheckManual: () async {
        return Failure<bool, Exception>(
          domain.ServerFailure.withContext(
            message: 'Update check timed out while waiting for updater completion',
          ),
        );
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.byKey(const ValueKey('updates_refresh_button')));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.gsSectionUpdates), findsWidgets);
    expect(
      find.textContaining('Update check timed out while waiting for updater completion'),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.configUpdateTechnicalCompletionSource}: ${ptL10n.configUpdateCompletionSourceCompletionTimeout}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.configUpdateTechnicalProbeRequestUrl}: https://example.com/appcast.xml?cb=1'),
      findsOneWidget,
    );
  });
}
