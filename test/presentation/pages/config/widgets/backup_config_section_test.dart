import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_config_section.dart';
import 'package:plug_agente/presentation/providers/presentation_infrastructure_providers.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class _FakeBackupService implements ILocalAppDataBackupService {
  _FakeBackupService({String? pendingFailure}) : _pendingFailure = pendingFailure;

  final String? _pendingFailure;
  int clearCount = 0;

  @override
  Future<String?> readPendingRestoreFailureDiagnostics() async => _pendingFailure;

  @override
  Future<void> clearRestoreFailureDiagnostics() async => clearCount++;

  @override
  int get liveAgentConfigSchemaVersion => 1;

  @override
  Future<Result<void>> exportBackupZip(
    String destinationZipPath, {
    bool includeSecureStorageSecrets = false,
  }) => throw UnimplementedError();

  @override
  Future<Result<RestoreStagingSnapshot>> stageRestoreFromZip(String zipPath) => throw UnimplementedError();

  @override
  Future<Result<void>> applyRestore(RestoreStagingSnapshot staging) => throw UnimplementedError();

  @override
  Future<void> writeRestoreFailureDiagnostics(Object failure) => throw UnimplementedError();

  @override
  void disposeStaging(RestoreStagingSnapshot staging) => throw UnimplementedError();
}

Future<void> _pumpBackupSection(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: buildPresentationInfrastructureProviders(
        capabilities: RuntimeCapabilities.full(),
      ),
      child: child,
    ),
  );
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('renders section title and diagnostics footnote (EN)', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: BackupConfigSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.configBackupSectionTitle), findsOneWidget);
    expect(find.textContaining('last_restore_error.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup_secure_storage_secrets_notice')), findsOneWidget);
    expect(find.text(l10n.configBackupSecureStorageSecretsNote), findsOneWidget);
    expect(find.byKey(const ValueKey('backup_include_secure_storage_secrets_checkbox')), findsOneWidget);
    expect(find.text(AppStrings.singleInstanceMessage), findsNothing);
  });

  testWidgets('shows secure storage export warning when opt-in checkbox is checked', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: BackupConfigSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('backup_include_secure_storage_secrets_warning')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('backup_include_secure_storage_secrets_checkbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('backup_include_secure_storage_secrets_warning')), findsOneWidget);
    expect(find.text(l10n.configBackupIncludeSecureStorageSecretsWarning), findsOneWidget);
  });

  testWidgets('shows AppStrings single-instance line in Portuguese locale', (tester) async {
    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: BackupConfigSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.singleInstanceMessage), findsOneWidget);
  });

  testWidgets('does not show restore failure notice when there is none', (tester) async {
    getIt.registerSingleton<ILocalAppDataBackupService>(_FakeBackupService());

    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(content: BackupConfigSection()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restore_failure_notice')), findsNothing);
  });

  testWidgets('surfaces pending restore failure diagnostics on open', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    getIt.registerSingleton<ILocalAppDataBackupService>(
      _FakeBackupService(pendingFailure: 'code: applyMissingDb\nmessage: staged db missing'),
    );

    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(content: BackupConfigSection()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restore_failure_notice')), findsOneWidget);
    expect(find.text(l10n.configBackupRestoreFailedNoticeTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('restore_failure_details')), findsOneWidget);
  });

  testWidgets('dismissing the notice clears diagnostics and hides it', (tester) async {
    final fake = _FakeBackupService(pendingFailure: 'code: applyMissingDb');
    getIt.registerSingleton<ILocalAppDataBackupService>(fake);

    await _pumpBackupSection(
      tester,
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(content: BackupConfigSection()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restore_failure_notice')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore_failure_dismiss_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restore_failure_notice')), findsNothing);
    expect(fake.clearCount, 1);
  });
}
