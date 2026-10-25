import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_installation_preparation_monitor.dart';
import 'package:result_dart/result_dart.dart';

/// A request owns its maintenance effects for the lifetime of this process.
class InstallationPreparationService implements IInstallationPreparation {
  InstallationPreparationService({
    required this.prepareMaintenance,
    required this.closeApplication,
    required this.cancelMaintenance,
  });
  final void Function() cancelMaintenance;
  bool _cancelled = false;
  @override
  void cancel() {
    _cancelled = true;
    cancelMaintenance();
  }

  final Future<Result<void>> Function(String operation) prepareMaintenance;
  final Future<void> Function() closeApplication;
  String? _operation;
  Future<Result<InstallationPreparationState>>? _preparation;
  @override
  InstallationPreparationState state = InstallationPreparationState.waiting;

  @override
  Future<Result<InstallationPreparationState>> prepare(String operation) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(operation) || (_operation != null && _operation != operation)) {
      return Future.value(Failure(domain.ValidationFailure('Solicitação de instalação inválida.')));
    }
    _operation = operation;
    return _preparation ??= _prepare(operation);
  }

  Future<Result<InstallationPreparationState>> _prepare(String operation) async {
    try {
      if (_cancelled) {
        state = InstallationPreparationState.cancelled;
        return Failure(domain.ConfigurationFailure('A preparação da instalação foi cancelada.'));
      }
      final result = await prepareMaintenance(operation);
      if (result.isError()) {
        final failure = result.exceptionOrNull();
        state =
            failure is domain.Failure &&
                (failure.context['outcome_unknown'] == true || failure.context['resources_closed'] == true)
            ? InstallationPreparationState.recoveryRequired
            : _cancelled
            ? InstallationPreparationState.cancelled
            : InstallationPreparationState.blocked;
        return Failure(failure!);
      }
      state = InstallationPreparationState.closing;
      return Success(state);
    } on Object catch (error) {
      state = InstallationPreparationState.recoveryRequired;
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'O encerramento precisa de recuperação.',
          cause: error,
          context: const {'outcome_unknown': true},
        ),
      );
    }
  }

  Future<Result<void>>? _closing;
  @override
  Future<Result<void>> close() {
    if (_closing != null) return _closing!;
    if (state != InstallationPreparationState.closing) return Future.value(const Success(unit));
    return _closing = _close();
  }

  Future<Result<void>> _close() async {
    try {
      await closeApplication();
      return const Success(unit);
    } on Object catch (error) {
      state = InstallationPreparationState.recoveryRequired;
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Não foi possível encerrar o aplicativo com segurança.',
          cause: error,
          context: const {'outcome_unknown': true},
        ),
      );
    }
  }
}
