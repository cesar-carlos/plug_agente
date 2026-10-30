import 'dart:typed_data';

import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoInputPipe {
  Future<Result<Unit>> write(Uint8List bytes);
  Future<Result<Unit>> close();
}

/// Acknowledged bytes are a lower bound, never proof of program consumption.
final class ActionIoPipeFailure extends ActionRuntimeFailure {
  ActionIoPipeFailure({this.confirmedBytes, super.cause})
    : super.withContext(
        message: 'The input delivery could not be confirmed.',
        code: 'ACTION_OUTCOME_UNKNOWN',
        context: {'retryable': false},
      );

  final int? confirmedBytes;

  @override
  Object? get diagnosticCause => cause?.runtimeType.toString();
}
