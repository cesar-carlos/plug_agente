import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/domain/actions/actions.dart';

/// Decodes captured child-process bytes using the configured output encoding policy.
abstract final class ActionProcessOutputDecoder {
  static String decode(
    List<int> bytes, {
    AgentActionOutputEncodingMode mode = AgentActionOutputEncodingMode.systemConsole,
  }) {
    if (bytes.isEmpty) {
      return '';
    }

    return switch (mode) {
      AgentActionOutputEncodingMode.utf8 => utf8.decode(bytes, allowMalformed: true),
      AgentActionOutputEncodingMode.systemConsole => _decodeSystemConsole(bytes),
    };
  }

  static String _decodeSystemConsole(List<int> bytes) {
    if (!Platform.isWindows) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    try {
      return systemEncoding.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
