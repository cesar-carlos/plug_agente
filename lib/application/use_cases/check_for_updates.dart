import 'package:plug_agente/application/services/update_service.dart';
import 'package:result_dart/result_dart.dart';

class CheckForUpdates {
  CheckForUpdates(this._service);
  final UpdateService _service;

  Future<Result<bool>> call() => _service.checkForUpdates();
}
