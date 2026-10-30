import 'dart:convert';
import 'dart:typed_data';

import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:result_dart/result_dart.dart';

abstract final class ActionIoRequestParser {
  static Result<ActionIoConfiguration> configuration(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => !const {'version', 'mode', 'close_input', 'initial_input_base64'}.contains(key)) ||
        value['version'] is! int ||
        value['version'] != ActionIoLimits.version ||
        value['mode'] != 'faithful' ||
        value['close_input'] is! bool) {
      return Failure(_invalid('io'));
    }
    Uint8List? initialInput;
    if (value.containsKey('initial_input_base64')) {
      final decoded = block(value['initial_input_base64']);
      if (decoded.isError()) return Failure(decoded.exceptionOrNull()!);
      initialInput = decoded.getOrThrow();
    }
    return Success(ActionIoConfiguration(closeInput: value['close_input'] as bool, initialInput: initialInput));
  }

  static Result<Uint8List> block(Object? value) {
    const maxEncodedLength = ((ActionIoLimits.blockBytes + 2) ~/ 3) * 4;
    if (value is! String || value.length > maxEncodedLength) return Failure(_invalid('data_base64'));
    try {
      final bytes = base64Decode(value);
      // The decoder accepts URL encoding, omitted padding and noncanonical pad bits.
      if (bytes.length > ActionIoLimits.blockBytes || base64Encode(bytes) != value) {
        return Failure(_invalid('data_base64'));
      }
      return Success(bytes);
    } on FormatException {
      return Failure(_invalid('data_base64'));
    }
  }

  static ActionValidationFailure _invalid(String field) => ActionValidationFailure.withContext(
    message: 'Invalid faithful I/O request.',
    code: 'ACTION_IO_INVALID_INPUT',
    context: {'field': field, 'phase': 'admission', 'effects_possible': false, 'retryable': false},
  );
}
