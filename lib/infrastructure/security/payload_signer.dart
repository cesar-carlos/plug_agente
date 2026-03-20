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
    final canonicalBytes = _canonicalizeUtf8(payload);
    final hmacValue = _computeHmacFromUtf8Bytes(canonicalBytes, secret);
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

    final canonicalBytes = _canonicalizeUtf8(payload);
    final expected = _computeHmacFromUtf8Bytes(canonicalBytes, secret);
    return _constantTimeEquals(expected, signature.value);
  }

  PayloadSignature signFrame(PayloadFrame frame) {
    final keyId = activeKeyId;
    final secret = _keys[keyId]!;
    final canonicalBytes =
        _canonicalizeFrameUtf8(frame.copyWith(clearSignature: true));
    final hmacValue = _computeHmacFromUtf8Bytes(canonicalBytes, secret);
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

    final canonicalBytes =
        _canonicalizeFrameUtf8(frame.copyWith(clearSignature: true));
    final expected = _computeHmacFromUtf8Bytes(canonicalBytes, secret);
    return _constantTimeEquals(expected, signature.value);
  }

  Uint8List _canonicalizeUtf8(Map<String, dynamic> payload) {
    final signable = <String, dynamic>{};
    if (payload.containsKey('method')) signable['method'] = payload['method'];
    if (payload.containsKey('id')) signable['id'] = payload['id'];
    if (payload.containsKey('params')) signable['params'] = payload['params'];
    if (payload.containsKey('result')) signable['result'] = payload['result'];
    if (payload.containsKey('error')) signable['error'] = payload['error'];
    final raw = JsonUtf8Encoder().convert(signable);
    return raw is Uint8List ? raw : Uint8List.fromList(raw);
  }

  Uint8List _canonicalizeFrameUtf8(PayloadFrame frame) {
    final payload = frame.payload;
    final payloadBytes = switch (payload) {
      final Uint8List value => value,
      final List<int> value => Uint8List.fromList(value),
      _ => Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    };
    final raw = JsonUtf8Encoder().convert(<String, dynamic>{
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
    return raw is Uint8List ? raw : Uint8List.fromList(raw);
  }

  String _computeHmacFromUtf8Bytes(Uint8List data, String secret) {
    final key = utf8.encode(secret);
    final digest = Hmac(sha256, key).convert(data);
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
