import 'package:result_dart/result_dart.dart';

import '../services/update_service.dart';
import '../../domain/errors/failures.dart' as domain;

class CheckForUpdates {
  final UpdateService _service;

  CheckForUpdates(this._service);

  Future<Result<bool>> call() async {
    try {
      final updateAvailable = await _service.checkForUpdates();
      return Success(updateAvailable);
    } catch (e) {
      return Failure(domain.ServerFailure('Failed to check for updates: $e'));
    }
  }
}
