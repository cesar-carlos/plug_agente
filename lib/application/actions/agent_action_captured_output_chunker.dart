import 'dart:convert';

import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';

/// One persisted UTF-8 chunk of captured stdout/stderr.
final class AgentActionCapturedOutputChunkSlice {
  const AgentActionCapturedOutputChunkSlice({
    required this.chunkIndex,
    required this.utf8Offset,
    required this.payload,
  });

  final int chunkIndex;
  final int utf8Offset;
  final String payload;
}

/// Splits redacted captured text into bounded Drift chunk rows.
abstract final class AgentActionCapturedOutputChunker {
  static bool shouldSpillToChunks(String text) {
    return utf8.encode(text).length > AgentActionCapturedOutputConstants.inlineMaxUtf8Bytes;
  }

  static List<AgentActionCapturedOutputChunkSlice> split(String text) {
    final bytes = utf8.encode(text);
    if (bytes.isEmpty) {
      return const <AgentActionCapturedOutputChunkSlice>[];
    }

    final chunkSize = AgentActionCapturedOutputConstants.chunkPayloadUtf8Bytes;
    final slices = <AgentActionCapturedOutputChunkSlice>[];
    var offset = 0;
    var index = 0;
    while (offset < bytes.length) {
      var end = (offset + chunkSize).clamp(offset, bytes.length);
      while (end > offset) {
        try {
          utf8.decode(bytes.sublist(offset, end), allowMalformed: false);
          break;
        } on FormatException {
          end--;
        }
      }
      if (end <= offset) {
        end = (offset + 1).clamp(offset, bytes.length);
      }
      slices.add(
        AgentActionCapturedOutputChunkSlice(
          chunkIndex: index,
          utf8Offset: offset,
          payload: utf8.decode(bytes.sublist(offset, end)),
        ),
      );
      offset = end;
      index++;
    }
    return slices;
  }
}
