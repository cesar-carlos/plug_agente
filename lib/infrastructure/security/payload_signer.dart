import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';

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

class PayloadSigner {
  PayloadSigner({required Map<String, String> keys}) : _keys = Map.of(keys);

  final Map<String, String> _keys;
  static const supportedAlgorithm = 'hmac-sha256';

  String get activeKeyId => _keys.keys.first;

  PayloadSignature sign(Map<String, dynamic> payload) {
    final keyId = activeKeyId;
    final secret = _keys[keyId]!;
    final canonical = _canonicalize(payload);
    final hmacValue = _computeHmac(canonical, secret);
    return PayloadSignature(
      alg: supportedAlgorithm,
      value: hmacValue,
      keyId: keyId,
    );
  }

  bool verify(Map<String, dynamic> payload, PayloadSignature signature) {
    if (signature.alg != supportedAlgorithm) return false;

    final secret = _keys[signature.keyId];
    if (secret == null) return false;

    final canonical = _canonicalize(payload);
    final expected = _computeHmac(canonical, secret);
    return _constantTimeEquals(expected, signature.value);
  }

  PayloadSignature signFrame(PayloadFrame frame) {
    final keyId = activeKeyId;
    final secret = _keys[keyId]!;
    final canonical = _canonicalizeFrame(frame.copyWith(clearSignature: true));
    final hmacValue = _computeHmac(canonical, secret);
    return PayloadSignature(
      alg: supportedAlgorithm,
      value: hmacValue,
      keyId: keyId,
    );
  }

  bool verifyFrame(PayloadFrame frame, PayloadSignature signature) {
    if (signature.alg != supportedAlgorithm) return false;

    final secret = _keys[signature.keyId];
    if (secret == null) return false;

    final canonical = _canonicalizeFrame(frame.copyWith(clearSignature: true));
    final expected = _computeHmac(canonical, secret);
    return _constantTimeEquals(expected, signature.value);
  }

  String _canonicalize(Map<String, dynamic> payload) {
    final signable = <String, dynamic>{};
    if (payload.containsKey('method')) signable['method'] = payload['method'];
    if (payload.containsKey('id')) signable['id'] = payload['id'];
    if (payload.containsKey('params')) signable['params'] = payload['params'];
    if (payload.containsKey('result')) signable['result'] = payload['result'];
    if (payload.containsKey('error')) signable['error'] = payload['error'];
    return jsonEncode(signable);
  }

  String _canonicalizeFrame(PayloadFrame frame) {
    final payload = frame.payload;
    final payloadBytes = switch (payload) {
      final Uint8List value => value,
      final List<int> value => Uint8List.fromList(value),
      _ => Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    };
    return jsonEncode({
      'schemaVersion': frame.schemaVersion,
      'enc': frame.enc,
      'cmp': frame.cmp,
      'contentType': frame.contentType,
      'originalSize': frame.originalSize,
      'compressedSize': frame.compressedSize,
      'traceId': frame.traceId,
      'requestId': frame.requestId,
      'payload': base64Encode(payloadBytes),
    });
  }

  String _computeHmac(String data, String secret) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(data);
    final digest = Hmac(sha256, key).convert(bytes);
    return base64Encode(digest.bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
