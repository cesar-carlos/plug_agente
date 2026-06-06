import 'dart:math' as math;

/// Inclusive ID range assigned to one parallel DML stress worker.
class OdbcDmlStressIdRange {
  const OdbcDmlStressIdRange(this.start, this.end);

  final int start;
  final int end;
}

/// Partitions [rowCount] row ids (1-based) across [concurrency] workers without overlap.
List<OdbcDmlStressIdRange> buildOdbcDmlStressIdRanges(
  int rowCount,
  int concurrency,
) {
  final workers = math.max(1, concurrency);
  final ranges = <OdbcDmlStressIdRange>[];
  var start = 1;
  final baseSize = rowCount ~/ workers;
  var remainder = rowCount % workers;

  for (var worker = 0; worker < workers; worker++) {
    final size = baseSize + (remainder > 0 ? 1 : 0);
    if (remainder > 0) {
      remainder--;
    }
    if (size <= 0) {
      continue;
    }
    final end = start + size - 1;
    ranges.add(OdbcDmlStressIdRange(start, end));
    start = end + 1;
  }
  return ranges;
}

/// Maps a per-iteration local row id (1..rowCount) to a globally unique primary key.
int odbcDmlStressRowId({
  required int iteration,
  required int rowCount,
  required int localId,
}) {
  return iteration * rowCount + localId;
}

/// Batch timeout that accounts for direct-lease queueing when workers exceed pool/direct caps.
int odbcDmlStressBatchTimeoutMs({
  required int rowCount,
  required int concurrency,
}) {
  final workers = math.max(1, concurrency);
  final rowsPerWorker = (rowCount + workers - 1) ~/ workers;
  // ~120ms/row with headroom for queued direct batch_transaction leases.
  final estimatedMs = workers * rowsPerWorker * 120;
  return math.max(120000, estimatedMs);
}
