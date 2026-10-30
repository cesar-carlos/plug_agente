import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/action_io_request_parser.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';

void main() {
  test('preserves arbitrary bytes, including invalid UTF8 and control bytes', () {
    final bytes = [0, 13, 10, 26, 255, 254, 128];
    expect(ActionIoRequestParser.block(base64Encode(bytes)).getOrThrow(), bytes);
  });

  test('accepts exactly one block and rejects decoded overflow at the same encoded length', () {
    expect(ActionIoRequestParser.block(base64Encode(List.filled(65536, 0))).isSuccess(), isTrue);
    expect(ActionIoRequestParser.block(base64Encode(List.filled(65537, 0))).isError(), isTrue);
  });

  test('rejects decoder normalization and malformed input without leaking content', () {
    for (final input in ['Zg', 'Zh==', '_w==', '%2Fw==', ' Zg==', 'secret!', null, 42]) {
      final result = ActionIoRequestParser.block(input);
      expect(result.isError(), isTrue, reason: '$input');
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, 'ACTION_IO_INVALID_INPUT');
      expect(failure.context['effects_possible'], isFalse);
      expect(failure.context.containsKey('payload'), isFalse);
    }
  });

  test('distinguishes absent initial input from an explicit empty message', () {
    final request = <String, dynamic>{'version': 1, 'mode': 'faithful', 'close_input': false};
    expect(ActionIoRequestParser.configuration(request).getOrThrow().initialInput, isNull);
    final configured = ActionIoRequestParser.configuration({...request, 'initial_input_base64': ''}).getOrThrow();
    expect(configured.initialInput, isEmpty);
    expect(configured.closeInput, isFalse);
  });

  test('rejects unknown keys, versions, coercions and null input', () {
    final request = <String, dynamic>{'version': 1, 'mode': 'faithful', 'close_input': false};
    for (final invalid in [
      {...request, 'version': 1.0},
      {...request, 'version': 2},
      {...request, 'mode': 'text'},
      {...request, 'close_input': 'false'},
      {...request, 'initial_input_base64': null},
      {...request, 'stdin': 'secret'},
      null,
    ]) {
      expect(ActionIoRequestParser.configuration(invalid).isError(), isTrue);
    }
  });

  test('configuration owns immutable bytes', () {
    final bytes = [1, 2, 3];
    final configuration = ActionIoConfiguration(closeInput: true, initialInput: bytes);
    bytes[0] = 9;
    expect(configuration.initialInput, [1, 2, 3]);
    expect(() => configuration.initialInput![0] = 8, throwsUnsupportedError);
  });
}
