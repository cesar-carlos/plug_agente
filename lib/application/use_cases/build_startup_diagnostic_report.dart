import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Support-ticket report for "the agent did not start with Windows".
///
/// Always succeeds: when the registry cannot be read, the failure itself goes
/// into the report, since that is exactly what support needs to see.
class BuildStartupDiagnosticReport {
  BuildStartupDiagnosticReport(
    this._repository, {
    StartupConfigurationSessionState? sessionState,
    IInstallerAutostartRequestStore? installerAutostartRequestStore,
    DateTime Function()? now,
  }) : _sessionState = sessionState,
       _installerAutostartRequestStore = installerAutostartRequestStore,
       _now = now ?? DateTime.now;

  static const String title = 'Plug Agente startup diagnostic';

  final IStartupPreferencesRepository _repository;
  final StartupConfigurationSessionState? _sessionState;
  final IInstallerAutostartRequestStore? _installerAutostartRequestStore;
  final DateTime Function() _now;

  Future<Result<String>> call() async {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln('Generated at (UTC): ${_now().toUtc().toIso8601String()}')
      ..writeln()
      ..writeln('[App state]')
      ..writeln('Stored startWithWindows preference: ${_repository.startWithWindows}')
      ..writeln(
        'Last --autostart launch (UTC): ${_repository.lastAutostartLaunchAt?.toUtc().toIso8601String() ?? 'never'}',
      )
      ..writeln('Installer auto-start request pending: ${await _describeInstallerRequest()}');
    _writeBootDiagnostics(buffer);

    buffer
      ..writeln()
      ..writeln('[Windows registry]');
    final registryReport = await _repository.buildStartupDiagnosticReport();
    registryReport.fold(
      buffer.writeln,
      (failure) => buffer.writeln('Registry diagnostic unavailable: $failure'),
    );

    return Success(buffer.toString().trimRight());
  }

  void _writeBootDiagnostics(StringBuffer buffer) {
    final diagnostics = _sessionState?.bootDiagnostics;
    if (diagnostics == null) {
      buffer.writeln('Boot auto-start step: not recorded');
      return;
    }

    final validation = diagnostics.launchConfigurationValidated
        ? 'validated (${diagnostics.launchConfiguration?.type.name ?? 'unchanged'})'
        : 'skipped';
    buffer
      ..writeln('Launched with --autostart this session: ${diagnostics.isAutostartLaunch}')
      ..writeln('Boot launch configuration: $validation');
    final failureCode = diagnostics.launchConfiguration?.startupFailureCode;
    if (failureCode != null) {
      buffer.writeln('Boot launch configuration failure code: ${failureCode.name}');
    }
  }

  Future<String> _describeInstallerRequest() async {
    final store = _installerAutostartRequestStore;
    if (store == null) {
      return 'unavailable';
    }
    try {
      return '${await store.hasPendingRequest()}';
    } on Object catch (error) {
      return 'read failed ($error)';
    }
  }
}
