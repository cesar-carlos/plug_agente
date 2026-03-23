import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';

/// Collects the single digest emitted by chunked SHA-256 conversion.
/// The crypto package's digest sink type is not part of its public export.
class _Sha256DigestCollector implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}

  Digest get value {
    final d = _digest;
    if (d == null) {
      throw StateError('SHA-256 chunked conversion produced no digest');
    }
    return d;
  }
}

/// Canonical JSON fingerprint for idempotency (stable key ordering).
///
/// Must stay aligned with historical agent behavior: same inputs produce the
/// same SHA-256 as before this module was extracted.
String buildIdempotencyFingerprintForEnvelope(Map<String, dynamic> envelope) {
  final canonicalPayload = canonicalizeJsonValueForIdempotency(envelope);
  final digestCollector = _Sha256DigestCollector();
  final hashSink = sha256.startChunkedConversion(digestCollector);
  final jsonSink = JsonUtf8Encoder().startChunkedConversion(hashSink);
  jsonSink.add(canonicalPayload);
  jsonSink.close();
  return digestCollector.value.toString();
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
    envelope,
    jsonPayloadIsolateEncodeThresholdBytes,
  )) {
    return compute(buildIdempotencyFingerprintForEnvelope, envelope);
  }
  return buildIdempotencyFingerprintForEnvelope(envelope);
}

dynamic canonicalizeJsonValueForIdempotency(dynamic value) {
  if (value is Map<String, dynamic>) {
    final entries = value.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      for (final e in entries)
        e.key: canonicalizeJsonValueForIdempotency(e.value),
    };
  }
  if (value is Map) {
    final normalized = <MapEntry<String, dynamic>>[];
    for (final e in value.entries) {
      normalized.add(
        MapEntry(
          e.key.toString(),
          canonicalizeJsonValueForIdempotency(e.value),
        ),
      );
    }
    normalized.sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      for (final e in normalized) e.key: e.value,
    };
  }
  if (value is List) {
    final len = value.length;
    if (len == 0) {
      return <dynamic>[];
    }
    return List<dynamic>.generate(
      len,
      (int i) => canonicalizeJsonValueForIdempotency(value[i]),
      growable: false,
    );
  }
  return value;
}
