import 'dart:convert';

import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/captured_output_utf8_window.dart';

/// Per-stream UTF-8 window for redacted stdout/stderr in JSON-RPC results.
final class AgentActionExecutionOutputPaging {
  const AgentActionExecutionOutputPaging({
    this.stdoutOffsetUtf8 = 0,
    this.stderrOffsetUtf8 = 0,
    this.maxOutputBytesPerStream = AgentActionRpcConstants.defaultMaxOutputBytesPerStream,
  });

  final int stdoutOffsetUtf8;
  final int stderrOffsetUtf8;
  final int maxOutputBytesPerStream;
}

int _alignUtf8StartOffset(List<int> bytes, int offset) {
  var o = offset.clamp(0, bytes.length);
  while (o > 0 && o < bytes.length && (bytes[o] & 0xC0) == 0x80) {
    o--;
  }
  return o;
}

CapturedOutputUtf8Window sliceUtf8TextWindow(
  String fullText,
  int offsetUtf8,
  int maxBytes,
) {
  final bytes = utf8.encode(fullText);
  final total = bytes.length;
  final start = _alignUtf8StartOffset(bytes, offsetUtf8);
  if (start >= total) {
    return (
      text: '',
      nextOffset: total,
      totalBytes: total,
      responseTruncated: false,
      effectiveStart: start,
    );
  }
  var end = (start + maxBytes).clamp(start, total);
  while (end > start) {
    try {
      final slice = bytes.sublist(start, end);
      utf8.decode(slice, allowMalformed: false);
      break;
    } on FormatException {
      end--;
    }
  }
  final slice = bytes.sublist(start, end);
  final decoded = utf8.decode(slice);
  final responseTruncated = end < total;
  return (
    text: decoded,
    nextOffset: end,
    totalBytes: total,
    responseTruncated: responseTruncated,
    effectiveStart: start,
  );
}

Map<String, dynamic> buildCapturedOutputRpcMap({
  required bool captured,
  required bool storageTruncated,
  required String? fullText,
  required int offsetUtf8,
  required int maxBytes,
  CapturedOutputUtf8Window? precomputedWindow,
}) {
  if (!captured) {
    return <String, dynamic>{
      'captured': false,
      'truncated': storageTruncated,
      'utf8_total_bytes': 0,
      'offset': 0,
      'next_offset': 0,
      'response_truncated': false,
    };
  }
  final CapturedOutputUtf8Window window;
  if (precomputedWindow != null) {
    window = precomputedWindow;
  } else if (fullText != null) {
    window = sliceUtf8TextWindow(fullText, offsetUtf8, maxBytes);
  } else {
    return <String, dynamic>{
      'captured': true,
      'truncated': storageTruncated,
      'utf8_total_bytes': 0,
      'offset': offsetUtf8,
      'next_offset': offsetUtf8,
      'response_truncated': false,
    };
  }
  return <String, dynamic>{
    'captured': true,
    'truncated': storageTruncated,
    'text': window.text,
    'utf8_total_bytes': window.totalBytes,
    'offset': window.effectiveStart,
    'next_offset': window.nextOffset,
    'response_truncated': window.responseTruncated,
  };
}
