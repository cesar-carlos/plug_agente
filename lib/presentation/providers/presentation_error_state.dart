import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/presentation/providers/presentation_operation_failures.dart';

@immutable
class PresentationErrorState {
  const PresentationErrorState({
    required this.message,
    this.canRetry = false,
  });

  final String message;
  final bool canRetry;

  static PresentationErrorState? fromFailure(
    Object failure, {
    bool log = true,
  }) {
    if (PresentationOperationFailures.isSilent(failure)) {
      return null;
    }

    if (failure is Failure) {
      if (log) {
        failure.log();
      }
      return PresentationErrorState(
        message: failure.toDisplayMessage(),
        canRetry: failure.isTransient,
      );
    }

    return PresentationErrorState(message: failure.toString());
  }
}
