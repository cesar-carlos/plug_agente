import 'dart:convert';
import 'dart:math' as math;

import 'package:plug_agente/domain/protocol/protocol.dart';

/// Decides whether a materialized SELECT should be emitted as chunks based on
/// its real row volume, rather than row count alone.
///
/// The scan stops at the promotion threshold and never retains serialized
/// copies of rows. Pagination and cursors are excluded by the caller.
final class SqlMaterializedStreamingPromotionPolicy {
  const SqlMaterializedStreamingPromotionPolicy();

  static const int _absoluteThresholdBytes = 512 * 1024;

  bool shouldPromote({
    required List<Map<String, dynamic>> rows,
    required TransportLimits limits,
  }) {
    final byteThreshold = math.min(
      _absoluteThresholdBytes,
      math.max(1, limits.maxDecodedPayloadBytes ~/ 4),
    );
    var bytes = 0;
    for (final row in rows) {
      bytes += JsonUtf8Encoder().convert(row).length + 1;
      if (bytes > byteThreshold) {
        return true;
      }
    }
    return false;
  }
}
