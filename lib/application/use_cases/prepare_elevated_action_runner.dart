import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_installer.dart';
import 'package:result_dart/result_dart.dart';

/// Installs the Windows scheduled task for elevated agent actions.
///
/// This use case is **only** invoked from the Agent Actions UI (manual prepare).
/// It must not run during app bootstrap; hub, SQL RPC, and the temporal scheduler
/// keep working when installation fails or UAC is denied.
class PrepareElevatedActionRunner {
  PrepareElevatedActionRunner(
    this._installer,
    this._readiness,
    this._storageContext,
  );

  final IElevatedActionRunnerInstaller _installer;
  final ElevatedActionRunnerReadinessService _readiness;
  final GlobalStorageContext _storageContext;

  Future<Result<ElevatedActionRunnerInstallStatus>> call() async {
    final before = await _installer.getStatus();
    if (before.state == ElevatedActionRunnerInstallState.unsupportedPlatform) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: before.state.name,
          context: {
            'user_message': 'A preparacao do executor elevado so esta disponivel no Windows.',
          },
        ),
      );
    }

    if (before.state == ElevatedActionRunnerInstallState.ready) {
      _readiness.refresh(_storageContext);
      _readiness.clearDegraded();
      return Success(before);
    }

    final installResult = await _installer.install(requestElevation: true);
    if (installResult.isError()) {
      return Failure(installResult.exceptionOrNull()!);
    }

    final after = await _installer.getStatus();
    if (!after.isReady) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated runner is still not ready after install attempt.',
          code: AgentActionFailureCode.elevatedNotConfigured,
          context: {
            'state': after.state.name,
            'user_message': 'A preparacao do executor elevado nao concluiu. Verifique o helper e a tarefa agendada.',
          },
        ),
      );
    }

    // Clear the degraded flag after a successful install so the UI reflects
    // the new ready state immediately without waiting for a manual refresh.
    _readiness.refresh(_storageContext);
    _readiness.clearDegraded();
    return Success(after);
  }
}
