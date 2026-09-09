import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_canonicalizer.dart';

class PayloadSignature {
  const PayloadSignature({
    required this.alg,
    required this.value,
    required this.keyId,
  });

  factory PayloadSignature.fromJson(Map<String, dynamic> json) {
    return PayloadSignature(
      alg: json['alg'] as String,
      value: json['value'] as String,
      keyId: json['key_id'] as String,
    );
  }

  final String alg;
  final String value;
  final String keyId;

  Map<String, dynamic> toJson() => {
    'alg': alg,
    'value': value,
    'key_id': keyId,
  };
}

class PayloadSigningMetrics {
  const PayloadSigningMetrics({
    required this.canonicalizeDurationUs,
    this.signDurationUs,
    this.verifyDurationUs,
  });

  final int canonicalizeDurationUs;
  final int? signDurationUs;
  final int? verifyDurationUs;
}

class PayloadSigningResult {
  const PayloadSigningResult({
    required this.signature,
    required this.metrics,
  });

  final PayloadSignature signature;
  final PayloadSigningMetrics metrics;
}

class PayloadVerificationResult {
  const PayloadVerificationResult({
    required this.isValid,
    required this.metrics,
  });

  final bool isValid;
  final PayloadSigningMetrics metrics;
}

class PayloadSigner {
  factory PayloadSigner({
    required Map<String, String> keys,
    String? activeKeyId,
  }) {
    final normalizedKeys = Map<String, String>.unmodifiable(_normalizeKeys(keys));
    if (normalizedKeys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'At least one signing key is required');
    }
    final keyBytes = Map<String, Uint8List>.unmodifiable({
      for (final entry in normalizedKeys.entries) entry.key: Uint8List.fromList(utf8.encode(entry.value)),
    });
    final resolvedActiveKeyId = _resolveActiveKeyId(normalizedKeys, activeKeyId);
    return PayloadSigner._(
      keys: normalizedKeys,
      keyBytes: keyBytes,
      activeKeyId: resolvedActiveKeyId,
    );
  }

  const PayloadSigner._({
    required Map<String, String> keys,
    required Map<String, Uint8List> keyBytes,
    required String activeKeyId,
  }) : _keys = keys,
       _keyBytes = keyBytes,
       _activeKeyId = activeKeyId;

  final Map<String, String> _keys;
  final Map<String, Uint8List> _keyBytes;
  final String _activeKeyId;
  static const supportedAlgorithm = 'hmac-sha256';

  String get activeKeyId => _activeKeyId;

  int get keyCount => _keys.length;

  List<String> get keyIds {
    final ids = _keys.keys.toList()..sort();
    return List.unmodifiable(ids);
  }

  PayloadSignature sign(Map<String, dynamic> payload) {
    final keyId = activeKeyId;
    final key = _keyBytes[keyId]!;
    final canonicalBytes = _canonicalizeUtf8(payload);
    final hmacValue = _computeHmacFromUtf8Bytes(canonicalBytes, key);
    return PayloadSignature(
      alg: supportedAlgorithm,
      value: hmacValue,
      keyId: keyId,
    );
  }

  bool verify(Map<String, dynamic> payload, PayloadSignature signature) {
    if (signature.alg != supportedAlgorithm) return false;

    final key = _keyBytes[signature.keyId];
    if (key == null) return false;

    final canonicalBytes = _canonicalizeUtf8(payload);
    final expected = _computeHmacFromUtf8Bytes(canonicalBytes, key);
    return _constantTimeEquals(expected, signature.value);
  }

  PayloadSignature signFrame(PayloadFrame frame) {
    return signFrameWithMetrics(frame).signature;
  }

  /// Async variant of [signFrameWithMetrics] that keeps canonicalization and
  /// HMAC work off the UI isolate for large transport frames.
  Future<PayloadSigningResult> signFrameAsync(PayloadFrame frame) async {
    final keyId = activeKeyId;
    final key = _keyBytes[keyId]!;
    final result = await compute(_signFrameIsolate, (_frameDataForIsolate(frame), key, keyId));

    return PayloadSigningResult(
      signature: PayloadSignature(
        alg: supportedAlgorithm,
        value: result['value']! as String,
        keyId: result['keyId']! as String,
      ),
      metrics: PayloadSigningMetrics(
        canonicalizeDurationUs: result['canonicalizeDurationUs']! as int,
        signDurationUs: result['signDurationUs']! as int,
      ),
    );
  }

  PayloadSigningResult signFrameWithMetrics(PayloadFrame frame) {
    final keyId = activeKeyId;
    final key = _keyBytes[keyId]!;
    final canonicalizeStopwatch = Stopwatch()..start();
    final canonicalBytes = _canonicalizeFrameUtf8(frame);
    canonicalizeStopwatch.stop();
    final signStopwatch = Stopwatch()..start();
    final hmacValue = _computeHmacFromUtf8Bytes(canonicalBytes, key);
    signStopwatch.stop();
    return PayloadSigningResult(
      signature: PayloadSignature(
        alg: supportedAlgorithm,
        value: hmacValue,
        keyId: keyId,
      ),
      metrics: PayloadSigningMetrics(
        canonicalizeDurationUs: canonicalizeStopwatch.elapsedMicroseconds,
        signDurationUs: signStopwatch.elapsedMicroseconds,
      ),
    );
  }

  bool verifyFrame(PayloadFrame frame, PayloadSignature signature) {
    return verifyFrameWithMetrics(frame, signature).isValid;
  }

  PayloadVerificationResult verifyFrameWithMetrics(PayloadFrame frame, PayloadSignature signature) {
    if (signature.alg != supportedAlgorithm) {
      return const PayloadVerificationResult(
        isValid: false,
        metrics: PayloadSigningMetrics(
          canonicalizeDurationUs: 0,
          verifyDurationUs: 0,
        ),
      );
    }

    final key = _keyBytes[signature.keyId];
    if (key == null) {
      return const PayloadVerificationResult(
        isValid: false,
        metrics: PayloadSigningMetrics(
          canonicalizeDurationUs: 0,
          verifyDurationUs: 0,
        ),
      );
    }

    final canonicalizeStopwatch = Stopwatch()..start();
    final canonicalBytes = _canonicalizeFrameUtf8(frame);
    canonicalizeStopwatch.stop();
    final verifyStopwatch = Stopwatch()..start();
    final expected = _computeHmacFromUtf8Bytes(canonicalBytes, key);
    final isValid = _constantTimeEquals(expected, signature.value);
    verifyStopwatch.stop();
    return PayloadVerificationResult(
      isValid: isValid,
      metrics: PayloadSigningMetrics(
        canonicalizeDurationUs: canonicalizeStopwatch.elapsedMicroseconds,
        verifyDurationUs: verifyStopwatch.elapsedMicroseconds,
      ),
    );
  }

  /// Verifies large transport frames off the UI isolate. Canonicalization is
  /// part of the isolate work so receive-side signature checks cannot monopolize
  /// the socket/UI isolate for large binary frames.
  Future<PayloadVerificationResult> verifyFrameAsyncWithMetrics(
    PayloadFrame frame,
    PayloadSignature signature,
  ) async {
    if (signature.alg != supportedAlgorithm) {
      return _invalidVerificationResult;
    }
    final key = _keyBytes[signature.keyId];
    if (key == null) {
      return _invalidVerificationResult;
    }
    final frameData = _frameDataForIsolate(frame);
    final result = await compute(_verifyFrameIsolate, (frameData, key, signature.value));
    return PayloadVerificationResult(
      isValid: result['isValid']! as bool,
      metrics: PayloadSigningMetrics(
        canonicalizeDurationUs: result['canonicalizeDurationUs']! as int,
        verifyDurationUs: result['verifyDurationUs']! as int,
      ),
    );
  }

  static const PayloadVerificationResult _invalidVerificationResult = PayloadVerificationResult(
    isValid: false,
    metrics: PayloadSigningMetrics(canonicalizeDurationUs: 0, verifyDurationUs: 0),
  );

  Uint8List _canonicalizeUtf8(Map<String, dynamic> payload) {
    return PayloadSigningCanonicalizer.canonicalizeLogicalPayload(payload);
  }

  Uint8List _canonicalizeFrameUtf8(PayloadFrame frame) {
    return PayloadSigningCanonicalizer.canonicalizeFrame(frame);
  }

  Map<String, dynamic> _frameDataForIsolate(PayloadFrame frame) {
    return <String, dynamic>{
      'schemaVersion': frame.schemaVersion,
      'enc': frame.enc,
      'cmp': frame.cmp,
      'contentType': frame.contentType,
      'originalSize': frame.originalSize,
      'compressedSize': frame.compressedSize,
      'payload': PayloadSigningCanonicalizer.payloadBytesForFrame(frame.payload),
      if (frame.traceId != null) 'traceId': frame.traceId,
      if (frame.requestId != null) 'requestId': frame.requestId,
    };
  }

  String _computeHmacFromUtf8Bytes(Uint8List data, Uint8List key) {
    final digest = Hmac(sha256, key).convert(data);
    return base64Encode(digest.bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    // Compare the raw digest bytes rather than base64 strings to avoid the
    // early-exit timing side channel on length difference. Both MACs are always
    // 32 bytes (SHA-256), so padding to a fixed length is always safe.
    final aBytes = base64Decode(_padBase64(a));
    final bBytes = base64Decode(_padBase64(b));
    final len = aBytes.length > bBytes.length ? aBytes.length : bBytes.length;
    var result = aBytes.length ^ bBytes.length; // non-zero if lengths differ
    for (var i = 0; i < len; i++) {
      result |= (i < aBytes.length ? aBytes[i] : 0) ^ (i < bBytes.length ? bBytes[i] : 0);
    }
    return result == 0;
  }

  static String _padBase64(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + '=' * (4 - mod);
  }

  static Map<String, String> _normalizeKeys(Map<String, String> keys) {
    final normalized = <String, String>{};
    for (final entry in keys.entries) {
      final keyId = entry.key.trim();
      final secret = entry.value.trim();
      if (keyId.isEmpty || secret.isEmpty) {
        continue;
      }
      normalized[keyId] = secret;
    }
    return normalized;
  }

  static String _resolveActiveKeyId(
    Map<String, String> keys,
    String? requestedActiveKeyId,
  ) {
    final active = requestedActiveKeyId?.trim();
    if (active == null || active.isEmpty) {
      return keys.keys.first;
    }
    if (!keys.containsKey(active)) {
      throw ArgumentError.value(
        requestedActiveKeyId,
        'activeKeyId',
        'Active signing key must exist in keys',
      );
    }
    return active;
  }
}

Map<String, Object> _signFrameIsolate((Map<String, dynamic>, Uint8List, String) args) {
  final (frameData, key, keyId) = args;
  final frame = PayloadFrame.fromJson(frameData);
  final canonicalizeStopwatch = Stopwatch()..start();
  final canonicalBytes = PayloadSigningCanonicalizer.canonicalizeFrame(frame);
  canonicalizeStopwatch.stop();
  final signStopwatch = Stopwatch()..start();
  final value = base64Encode(Hmac(sha256, key).convert(canonicalBytes).bytes);
  signStopwatch.stop();
  return <String, Object>{
    'value': value,
    'keyId': keyId,
    'canonicalizeDurationUs': canonicalizeStopwatch.elapsedMicroseconds,
    'signDurationUs': signStopwatch.elapsedMicroseconds,
  };
}

Map<String, Object> _verifyFrameIsolate((Map<String, dynamic>, Uint8List, String) args) {
  final (frameData, key, suppliedSignature) = args;
  final frame = PayloadFrame.fromJson(frameData);
  final canonicalizeStopwatch = Stopwatch()..start();
  final canonicalBytes = PayloadSigningCanonicalizer.canonicalizeFrame(frame);
  canonicalizeStopwatch.stop();
  final verifyStopwatch = Stopwatch()..start();
  final expected = base64Encode(Hmac(sha256, key).convert(canonicalBytes).bytes);
  final isValid = _constantTimeEqualsIsolate(expected, suppliedSignature);
  verifyStopwatch.stop();
  return <String, Object>{
    'isValid': isValid,
    'canonicalizeDurationUs': canonicalizeStopwatch.elapsedMicroseconds,
    'verifyDurationUs': verifyStopwatch.elapsedMicroseconds,
  };
}

bool _constantTimeEqualsIsolate(String expected, String actual) {
  try {
    final expectedBytes = base64Decode(_padBase64Isolate(expected));
    final actualBytes = base64Decode(_padBase64Isolate(actual));
    final length = expectedBytes.length > actualBytes.length ? expectedBytes.length : actualBytes.length;
    var difference = expectedBytes.length ^ actualBytes.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < expectedBytes.length ? expectedBytes[index] : 0) ^
          (index < actualBytes.length ? actualBytes[index] : 0);
    }
    return difference == 0;
  } on FormatException {
    return false;
  }
}

String _padBase64Isolate(String value) {
  final remainder = value.length % 4;
  return remainder == 0 ? value : '$value${'=' * (4 - remainder)}';
}
