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

  /// Drops a trailing incomplete UTF-8 sequence so truncation cannot split a code point.
  static List<int> clipIncompleteTrailingUtf8(List<int> bytes) {
    if (bytes.isEmpty) {
      return bytes;
    }

    var end = bytes.length;
    while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
      end--;
    }
    if (end == 0) {
      return const <int>[];
    }

    final lead = bytes[end - 1];
    final expectedLength = _utf8SequenceLength(lead);
    if (expectedLength <= 0 || (end - 1) + expectedLength > bytes.length) {
      return end == 1 ? const <int>[] : bytes.sublist(0, end - 1);
    }

    return bytes;
  }

  static int _utf8SequenceLength(int lead) {
    if (lead <= 0x7F) {
      return 1;
    }
    if (lead >= 0xC2 && lead <= 0xDF) {
      return 2;
    }
    if (lead >= 0xE0 && lead <= 0xEF) {
      return 3;
    }
    if (lead >= 0xF0 && lead <= 0xF4) {
      return 4;
    }
    return -1;
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
