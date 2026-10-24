import 'dart:convert';
import 'dart:math' as math;

import 'package:plug_agente/domain/protocol/protocol.dart';

/// Decides whether a materialized SELECT should be emitted as chunks based on
/// its real row volume, rather than row count alone.
///
/// The scan stops at the promotion threshold. A row whose structural lower
/// bound already exceeds the remaining budget is not encoded, and neither is a
/// row whose worst-case size still fits. Pagination and cursors are excluded
/// by the caller.
final class SqlMaterializedStreamingPromotionPolicy {
  const SqlMaterializedStreamingPromotionPolicy();

  static const int _absoluteThresholdBytes = 512 * 1024;
  static final JsonUtf8Encoder _jsonUtf8Encoder = JsonUtf8Encoder();

  bool shouldPromote({
    required List<Map<String, dynamic>> rows,
    required TransportLimits limits,
  }) {
    final byteThreshold = math.min(
      _absoluteThresholdBytes,
      math.max(1, limits.maxDecodedPayloadBytes ~/ 4),
    );
    var bytes = 0;
    var pendingUpper = 0;
    final pending = <Map<String, dynamic>>[];
    for (final row in rows) {
      final volume = _rowVolume(
        row,
        exceedBudget: byteThreshold - bytes - 1,
        fitBudget: byteThreshold - bytes - pendingUpper - 1,
      );
      switch (volume) {
        case _RowExceeds():
          return true;
        case _RowFits(:final upper):
          pending.add(row);
          pendingUpper += upper + 1;
        case _RowMeasure():
          for (final pendingRow in pending) {
            bytes += _jsonUtf8Encoder.convert(pendingRow).length + 1;
            if (bytes > byteThreshold) {
              return true;
            }
          }
          pending.clear();
          pendingUpper = 0;
          bytes += _jsonUtf8Encoder.convert(row).length + 1;
          if (bytes > byteThreshold) {
            return true;
          }
      }
    }
    return false;
  }
}

sealed class _RowVolume {
  const _RowVolume();
}

final class _RowExceeds extends _RowVolume {
  const _RowExceeds();
}

final class _RowFits extends _RowVolume {
  const _RowFits(this.upper);

  final int upper;
}

final class _RowMeasure extends _RowVolume {
  const _RowMeasure();
}

/// [exceedBudget] ignores pending worst-case slack so an earlier loose estimate
/// cannot promote a later row. [fitBudget] includes that slack, so a row is
/// kept unencoded only when even its maximum cannot cross the threshold.
_RowVolume _rowVolume(
  Map<String, dynamic> row, {
  required int exceedBudget,
  required int fitBudget,
}) {
  var minimum = 2;
  var upper = 2;
  var fieldIndex = 0;
  for (final entry in row.entries) {
    if (fieldIndex > 0) {
      minimum += 1;
      upper += 1;
    }
    minimum += entry.key.length + 3;
    upper += entry.key.length * _jsonStringCharacterUpperBound + 3;
    final valueMinimum = _jsonValueLowerBound(entry.value);
    final valueUpper = _jsonValueUpperBound(entry.value);
    if (valueMinimum == null || valueUpper == null) {
      return const _RowMeasure();
    }
    minimum += valueMinimum;
    upper += valueUpper;
    fieldIndex++;
    if (minimum > exceedBudget) {
      return const _RowExceeds();
    }
  }
  if (minimum > exceedBudget) {
    return const _RowExceeds();
  }
  if (upper <= fitBudget) {
    return _RowFits(upper);
  }
  return const _RowMeasure();
}

/// A JSON string code unit expands to at most six UTF-8 bytes (`\uXXXX`).
const int _jsonStringCharacterUpperBound = 6;

/// `num.toString()` as emitted by the JSON encoder.
///
/// A 64-bit int is at most 20 characters and a round-trip double stays under 32.
const int _jsonNumberUpperBoundCharacters = 32;

int? _jsonValueLowerBound(Object? value) {
  return switch (value) {
    null => 4,
    true => 4,
    false => 5,
    final String text => text.length + 2,
    num() => 1,
    _ => null,
  };
}

int? _jsonValueUpperBound(Object? value) {
  return switch (value) {
    null => 4,
    true => 4,
    false => 5,
    final String text => text.length * _jsonStringCharacterUpperBound + 2,
    num() => _jsonNumberUpperBoundCharacters,
    _ => null,
  };
}
