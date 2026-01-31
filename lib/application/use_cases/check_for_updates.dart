import 'package:plug_agente/application/services/update_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class CheckForUpdates {
  CheckForUpdates(this._service);
  final UpdateService _service;

  Future<Result<bool>> call() async {
    try {
      final updateAvailable = await _service.checkForUpdates();
      return Success(updateAvailable);
    } on Exception catch (e) {
      return Failure(domain.ServerFailure('Failed to check for updates: $e'));
    }
  }
}
