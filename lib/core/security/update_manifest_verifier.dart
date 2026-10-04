import 'dart:convert';

import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ValidationFailure;
import 'package:result_dart/result_dart.dart';

/// Python, Dart and the native worker sign the same compact, sorted UTF-8 JSON.
/// Reject noncanonical representations (including duplicate keys) before use.
String canonicalUpdateManifest(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalUpdateManifest(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonicalUpdateManifest).join(',')}]';
  if (value is String || value is int || value is bool || value == null) return jsonEncode(value);
  throw const FormatException('Unsupported manifest value');
}

class UpdateManifestVerifier {
  UpdateManifestVerifier({IAppcastSignatureVerifier? signatures})
    : _signatures = signatures ?? Ed25519AppcastSignatureVerifier();

  final IAppcastSignatureVerifier _signatures;

  Future<Result<Map<String, dynamic>>> verify({
    required Map<String, dynamic> envelope,
    required String publicKeys,
    required String expectedVersion,
    required String expectedChannel,
    required int expectedSize,
    required String expectedSha256,
  }) async {
    try {
      _fields(envelope, {'formatVersion', 'payloadBase64', 'signatureBase64'});
      if (envelope['formatVersion'] is! int || envelope['formatVersion'] != 1) {
        throw const FormatException('Unsupported envelope');
      }
      final encoded = envelope['payloadBase64'] as String;
      if (encoded.length > 90000) throw const FormatException('Manifest too large');
      final bytes = base64Decode(encoded);
      if (bytes.length > 65536) throw const FormatException('Manifest too large');
      final canonical = utf8.decode(bytes);
      final verified = await _signatures.verifyEnclosure(
        canonicalPayload: canonical,
        base64Signature: envelope['signatureBase64'] as String,
        base64PublicKey: publicKeys,
      );
      if (verified != AppcastSignatureVerificationStatus.valid) {
        throw const FormatException('Manifest signature rejected');
      }
      final payload = jsonDecode(canonical) as Map<String, dynamic>;
      if (canonicalUpdateManifest(payload) != canonical) throw const FormatException('Noncanonical manifest');
      _fields(payload, {
        'formatVersion',
        'version',
        'channel',
        'installer',
        'requirements',
        'protocol',
        'data',
        'release',
      });
      final version = payload['version'] as String;
      if (version.length > 128 ||
          !RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(version) ||
          version != expectedVersion ||
          payload['channel'] != expectedChannel ||
          !{'stable', 'beta', 'internal'}.contains(expectedChannel) ||
          payload['formatVersion'] is! int ||
          payload['formatVersion'] != 1) {
        throw const FormatException('Manifest identity rejected');
      }
      final installer = payload['installer'] as Map<String, dynamic>;
      final release = payload['release'] as Map<String, dynamic>;
      _fields(release, {'commit', 'tag'});
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(release['commit'] as String) ||
          release['tag'] != 'v${version.split('+').first}') {
        throw const FormatException('Manifest source rejected');
      }
      _fields(installer, {'name', 'size', 'sha256'});
      if (installer['name'] != 'PlugAgente-Setup-${version.split('+').first}.exe' ||
          installer['size'] is! int ||
          installer['size'] != expectedSize ||
          expectedSize <= 0 ||
          installer['sha256'] != expectedSha256 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
        throw const FormatException('Manifest installer rejected');
      }
      final protocol = payload['protocol'] as Map<String, dynamic>;
      _fields(protocol, {'host', 'worker'});
      if (protocol['host'] is! int || protocol['worker'] is! int || protocol['host'] != 1 || protocol['worker'] != 1) {
        throw const FormatException('Unsupported updater protocol');
      }
      final data = payload['data'] as Map<String, dynamic>;
      _fields(data, {'schema', 'rollbackProtocol'});
      if (data['schema'] is! int ||
          (data['schema'] as int) <= 0 ||
          data['rollbackProtocol'] is! int ||
          data['rollbackProtocol'] != 1) {
        throw const FormatException('Unsupported recovery protocol');
      }
      final requirements = List<String>.from(payload['requirements'] as List);
      if (requirements.toSet().length != requirements.length ||
          requirements.any((entry) => !RegExp(r'^[a-z][a-z0-9._-]{0,63}$').hasMatch(entry))) {
        throw const FormatException('Invalid requirements');
      }
      return Success(payload);
    } on Object catch (error) {
      return Failure(
        ValidationFailure.withContext(
          message: 'O manifesto da atualização não pôde ser validado.',
          cause: error,
          context: const {'reason': 'manifest_rejected'},
        ),
      );
    }
  }

  void _fields(Map<String, dynamic> object, Set<String> fields) {
    if (object.length != fields.length || !fields.every(object.containsKey)) {
      throw const FormatException('Invalid manifest fields');
    }
  }
}
