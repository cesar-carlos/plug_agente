import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/agent_action_captured_output_chunker.dart';
import 'package:plug_agente/domain/actions/captured_output_utf8_window.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

/// Drift persistence for spilled stdout/stderr captured output.
final class AgentActionCapturedOutputChunkStore {
  AgentActionCapturedOutputChunkStore(this._database);

  final AppDatabase _database;

  /// Replaces all chunk rows for [stream] on [executionId].
  ///
  /// When `PRAGMA foreign_keys=ON`, the parent execution row must already exist
  /// and this method must run in the same Drift `Transaction` as that insert.
  /// `AgentActionRepository.saveExecution` satisfies both requirements.
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
        .where((status) => status.isTerminal)
        .map((status) => status.name)
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
    final table = _database.agentActionCapturedOutputChunkTable;
    final lastQuery = _database.select(table)
      ..where((row) => row.executionId.equals(executionId) & row.stream.equals(stream))
      ..orderBy([(row) => OrderingTerm.desc(row.chunkIndex)])
      ..limit(1);
    final last = await lastQuery.getSingleOrNull();
    if (last == null) {
      return null;
    }

    final totalBytes = last.utf8Offset + utf8.encode(last.payload).length;
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
    final startMetaQuery = _database.selectOnly(table)
      ..addColumns([table.chunkIndex, table.utf8Offset])
      ..where(
        table.executionId.equals(executionId) &
            table.stream.equals(stream) &
            table.utf8Offset.isSmallerOrEqualValue(safeOffset),
      )
      ..orderBy([OrderingTerm.desc(table.utf8Offset)])
      ..limit(1);
    final startMeta = await startMetaQuery.getSingleOrNull();
    final startChunkIndex = startMeta?.read(table.chunkIndex);
    if (startChunkIndex == null) {
      return (
        text: '',
        nextOffset: totalBytes,
        totalBytes: totalBytes,
        responseTruncated: false,
        effectiveStart: safeOffset,
      );
    }

    final rows =
        await (_database.select(table)
              ..where(
                (row) =>
                    row.executionId.equals(executionId) &
                    row.stream.equals(stream) &
                    row.chunkIndex.isBiggerOrEqualValue(startChunkIndex) &
                    row.utf8Offset.isSmallerThanValue(targetEnd),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.chunkIndex)]))
            .get();
    if (rows.isEmpty) {
      return (
        text: '',
        nextOffset: totalBytes,
        totalBytes: totalBytes,
        responseTruncated: false,
        effectiveStart: safeOffset,
      );
    }

    final bytesBuilder = BytesBuilder(copy: false);
    for (final row in rows) {
      bytesBuilder.add(utf8.encode(row.payload));
    }
    final assembled = bytesBuilder.takeBytes();
    final assembledStart = rows.first.utf8Offset;
    final relativeStart = _alignUtf8StartOffset(assembled, safeOffset - assembledStart);
    final window = _decodeUtf8Window(assembled, relativeStart, maxBytes);
    final absoluteStart = assembledStart + relativeStart;
    final absoluteEnd = assembledStart + window.end;
    return (
      text: window.text,
      nextOffset: absoluteEnd,
      totalBytes: totalBytes,
      responseTruncated: absoluteEnd < totalBytes,
      effectiveStart: absoluteStart,
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

int _alignUtf8StartOffset(List<int> bytes, int offset) {
  var aligned = offset.clamp(0, bytes.length);
  while (aligned > 0 && aligned < bytes.length && (bytes[aligned] & 0xC0) == 0x80) {
    aligned--;
  }
  return aligned;
}

({int end, String text}) _decodeUtf8Window(List<int> bytes, int start, int maxBytes) {
  var end = math.min(start + maxBytes, bytes.length);
  while (end > start) {
    try {
      final slice = bytes.sublist(start, end);
      return (end: end, text: utf8.decode(slice, allowMalformed: false));
    } on FormatException {
      end--;
    }
  }
  return (end: start, text: '');
}
