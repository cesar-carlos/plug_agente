import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/application/use_cases/build_startup_diagnostic_report.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

class _MockInstallerAutostartRequestStore extends Mock implements IInstallerAutostartRequestStore {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late StartupConfigurationSessionState sessionState;
  final generatedAt = DateTime.utc(2026, 9, 25, 12);

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    sessionState = StartupConfigurationSessionState();
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.lastAutostartLaunchAt).thenReturn(DateTime.utc(2026, 9, 25, 8, 30));
    when(() => repository.buildStartupDiagnosticReport()).thenAnswer(
      (_) async => const Success('Scope: HKCU\n  Exists: true'),
    );
  });

  BuildStartupDiagnosticReport createUseCase({IInstallerAutostartRequestStore? store}) {
    return BuildStartupDiagnosticReport(
      repository,
      sessionState: sessionState,
      installerAutostartRequestStore: store,
      now: () => generatedAt,
    );
  }

  test('combines app state, boot diagnostics, and the registry section', () async {
    final store = _MockInstallerAutostartRequestStore();
    when(store.hasPendingRequest).thenAnswer((_) async => true);
    sessionState.recordBootDiagnostics(
      const StartupBootDiagnostics(
        isAutostartLaunch: true,
        launchConfigurationValidated: true,
        launchConfiguration: StartupLaunchConfigurationOutcome(
          StartupLaunchConfigurationOutcomeType.repairFailed,
          startupFailureCode: StartupServiceFailureCode.accessDenied,
        ),
      ),
    );

    final report = (await createUseCase(store: store)()).getOrThrow();

    expect(report, startsWith(BuildStartupDiagnosticReport.title));
    expect(report, contains('Generated at (UTC): 2026-09-25T12:00:00.000Z'));
    expect(report, contains('Stored startWithWindows preference: true'));
    expect(report, contains('Last --autostart launch (UTC): 2026-09-25T08:30:00.000Z'));
    expect(report, contains('Installer auto-start request pending: true'));
    expect(report, contains('Launched with --autostart this session: true'));
    expect(report, contains('Boot launch configuration: validated (repairFailed)'));
    expect(report, contains('Boot launch configuration failure code: accessDenied'));
    expect(report, contains('[Windows registry]\nScope: HKCU'));
  });

  test('reports missing session data and never-launched autostart explicitly', () async {
    when(() => repository.lastAutostartLaunchAt).thenReturn(null);

    final report = (await createUseCase()()).getOrThrow();

    expect(report, contains('Last --autostart launch (UTC): never'));
    expect(report, contains('Installer auto-start request pending: unavailable'));
    expect(report, contains('Boot auto-start step: not recorded'));
  });

  test('still succeeds with the registry failure and installer read error in the report', () async {
    final store = _MockInstallerAutostartRequestStore();
    when(store.hasPendingRequest).thenThrow(const FileSystemException('Access denied'));
    when(() => repository.buildStartupDiagnosticReport()).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(
          message: 'Permission denied when querying auto-start in HKCU.',
          startupCode: StartupServiceFailureCode.accessDenied,
        ),
      ),
    );

    final result = await createUseCase(store: store)();

    expect(result.isSuccess(), isTrue);
    final report = result.getOrThrow();
    expect(report, contains('Installer auto-start request pending: read failed'));
    expect(report, contains('Registry diagnostic unavailable'));
    expect(report, contains('Permission denied when querying auto-start in HKCU.'));
  });
}
