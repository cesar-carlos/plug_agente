import 'package:plug_agente/domain/errors/failures.dart';

/// Presentation-layer failures that should not surface in provider error state.
abstract final class PresentationOperationFailures {
  static final superseded = ValidationFailure.withContext(
    message: 'Superseded by a newer request',
    code: 'SUPERSEDED',
  );

  static final operationBlocked = ValidationFailure.withContext(
    message: 'Another operation is already in progress',
    code: 'OPERATION_BLOCKED',
  );

  static bool isSilent(Object failure) {
    if (failure is! Failure) {
      return false;
    }
    return failure.code == 'SUPERSEDED' || failure.code == 'OPERATION_BLOCKED';
  }
}
