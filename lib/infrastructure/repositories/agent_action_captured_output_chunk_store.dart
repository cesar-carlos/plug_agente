import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:plug_agente/application/actions/agent_action_captured_output_chunker.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/captured_output_utf8_window.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

/// Drift persistence for spilled stdout/stderr captured output.
final class AgentActionCapturedOutputChunkStore {
  AgentActionCapturedOutputChunkStore(this._database);

  final AppDatabase _database;

  Future<void> replaceStream({
    required String executionId,
    required String stream,
    required String text,
  }) async {
    await (_database.delete(_database.agentActionCapturedOutputChunkTable)..where(
          (table) => table.executionId.equals(executionId) & table.stream.equals(stream),
        ))
        .go();

    final slices = AgentActionCapturedOutputChunker.split(text);
    if (slices.isEmpty) {
      return;
    }

    await _database.batch((batch) {
      for (final slice in slices) {
        batch.insert(
          _database.agentActionCapturedOutputChunkTable,
          AgentActionCapturedOutputChunkTableCompanion.insert(
            executionId: executionId,
            stream: stream,
            chunkIndex: slice.chunkIndex,
            utf8Offset: slice.utf8Offset,
            payload: slice.payload,
          ),
        );
      }
    });
  }

  Future<void> deleteForExecution(String executionId) async {
    await (_database.delete(
      _database.agentActionCapturedOutputChunkTable,
    )..where((table) => table.executionId.equals(executionId))).go();
  }

  Future<void> deleteForTerminalExecutionsOlderThan(DateTime olderThan) async {
    final terminalStatusNames = AgentActionExecutionStatus.values
        .where((AgentActionExecutionStatus status) => status.isTerminal)
        .map((AgentActionExecutionStatus status) => status.name)
        .toList(growable: false);
    final executionIds = _database.agentActionExecutionTable.id;
    final finishedBefore = _database.agentActionExecutionTable.finishedAt.isSmallerThanValue(olderThan);
    final requestedBefore = _database.agentActionExecutionTable.requestedAt.isSmallerThanValue(olderThan);
    final isTerminal = _database.agentActionExecutionTable.status.isIn(terminalStatusNames);
    final subquery = _database.selectOnly(_database.agentActionExecutionTable)
      ..addColumns([executionIds])
      ..where(isTerminal & (finishedBefore | requestedBefore));

    await (_database.delete(
      _database.agentActionCapturedOutputChunkTable,
    )..where((table) => table.executionId.isInQuery(subquery))).go();
  }

  Future<CapturedOutputUtf8Window?> sliceStreamWindow({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async {
    final rows =
        await (_database.select(_database.agentActionCapturedOutputChunkTable)
              ..where(
                (table) => table.executionId.equals(executionId) & table.stream.equals(stream),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.chunkIndex),
              ]))
            .get();
    if (rows.isEmpty) {
      return null;
    }

    var totalBytes = 0;
    for (final row in rows) {
      totalBytes += utf8.encode(row.payload).length;
    }

    final safeOffset = offsetUtf8.clamp(0, totalBytes);
    if (safeOffset >= totalBytes) {
      return (
        text: '',
        nextOffset: totalBytes,
        totalBytes: totalBytes,
        responseTruncated: false,
        effectiveStart: safeOffset,
      );
    }

    final targetEnd = math.min(safeOffset + maxBytes, totalBytes);
    final bytesBuilder = BytesBuilder(copy: false);
    var cursor = 0;
    for (var index = 0; index < rows.length; index++) {
      final chunkBytes = utf8.encode(rows[index].payload);
      final chunkStart = cursor;
      final chunkEnd = cursor + chunkBytes.length;
      if (chunkEnd > safeOffset && chunkStart < targetEnd) {
        final takeStart = math.max(0, safeOffset - chunkStart);
        final takeEnd = math.min(chunkBytes.length, targetEnd - chunkStart);
        if (takeEnd > takeStart) {
          bytesBuilder.add(chunkBytes.sublist(takeStart, takeEnd));
        }
      }
      cursor = chunkEnd;
    }

    final sliceBytes = bytesBuilder.takeBytes();
    return (
      text: utf8.decode(sliceBytes),
      nextOffset: targetEnd,
      totalBytes: totalBytes,
      responseTruncated: targetEnd < totalBytes,
      effectiveStart: safeOffset,
    );
  }

  Future<String?> loadConcatenatedStream({
    required String executionId,
    required String stream,
  }) async {
    final rows =
        await (_database.select(_database.agentActionCapturedOutputChunkTable)
              ..where(
                (table) => table.executionId.equals(executionId) & table.stream.equals(stream),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.chunkIndex),
              ]))
            .get();
    if (rows.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.write(row.payload);
    }
    return buffer.toString();
  }

  static String streamNameForStdout() => AgentActionCapturedOutputConstants.stdoutStream;

  static String streamNameForStderr() => AgentActionCapturedOutputConstants.stderrStream;
}
