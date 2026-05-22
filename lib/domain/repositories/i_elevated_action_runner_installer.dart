import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract class IElevatedActionRunnerInstaller {
  Future<ElevatedActionRunnerInstallStatus> getStatus();

  Future<Result<void>> install({required bool requestElevation});
}
