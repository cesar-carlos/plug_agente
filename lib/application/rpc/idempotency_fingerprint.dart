import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';

/// Canonical JSON fingerprint for idempotency (stable key ordering).
///
/// Must stay aligned with historical agent behavior: same inputs produce the
/// same SHA-256 as before this module was extracted.
String buildIdempotencyFingerprintForEnvelope(Map<String, dynamic> envelope) {
  final canonicalPayload = canonicalizeJsonValueForIdempotency(envelope);
  final encoded = jsonEncode(canonicalPayload);
  return sha256.convert(utf8.encode(encoded)).toString();
}

/// Resolves fingerprint on the main isolate or in a worker when [params] are
/// large enough that canonicalization + JSON + hash would risk UI jank.
Future<String> resolveIdempotencyFingerprint(
  String method,
  Map<String, dynamic> params,
) async {
  final envelope = <String, dynamic>{
    'method': method,
    'params': params,
  };
  if (jsonTreeLikelyExceedsByteBudget(
    params,
    jsonPayloadIsolateEncodeThresholdBytes,
  )) {
    return compute(buildIdempotencyFingerprintForEnvelope, envelope);
  }
  return buildIdempotencyFingerprintForEnvelope(envelope);
}

dynamic canonicalizeJsonValueForIdempotency(dynamic value) {
  if (value is Map<String, dynamic>) {
    final sortedKeys = value.keys.toList(growable: false)..sort();
    return <String, dynamic>{
      for (final String key in sortedKeys)
        key: canonicalizeJsonValueForIdempotency(value[key]),
    };
  }
  if (value is Map) {
    final normalized = value.map(
      (dynamic key, dynamic v) =>
          MapEntry(key.toString(), canonicalizeJsonValueForIdempotency(v)),
    );
    final sortedKeys = normalized.keys.toList(growable: false)..sort();
    return <String, dynamic>{
      for (final String key in sortedKeys) key: normalized[key],
    };
  }
  if (value is List) {
    return value
        .map(canonicalizeJsonValueForIdempotency)
        .toList(
          growable: false,
        );
  }
  return value;
}
