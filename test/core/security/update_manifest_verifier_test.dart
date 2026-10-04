import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/security/update_manifest_verifier.dart';

void main() {
  late Map<String, dynamic> fixture;
  setUp(() {
    fixture = jsonDecode(File('test/fixtures/updater_manifest_v1.json').readAsStringSync()) as Map<String, dynamic>;
  });
  Future<bool> verify(Map<String, dynamic> envelope, {String channel = 'stable'}) async =>
      (await UpdateManifestVerifier().verify(
        envelope: envelope,
        publicKeys: fixture['publicKey'] as String,
        expectedVersion: '1.8.6+1',
        expectedChannel: channel,
        expectedSize: 123,
        expectedSha256: List.filled(64, 'a').join(),
      )).isSuccess();
  test('accepts the same canonical signed bytes as Python and C++', () async {
    expect(await verify(fixture['envelope'] as Map<String, dynamic>), isTrue);
    final payload = fixture['payload'] as Map<String, dynamic>;
    expect(
      canonicalUpdateManifest(payload),
      utf8.decode(base64Decode((fixture['envelope'] as Map)['payloadBase64'] as String)),
    );
  });
  test('rejects identity from another channel', () async {
    expect(await verify(fixture['envelope'] as Map<String, dynamic>, channel: 'beta'), isFalse);
  });
  test('rejects missing signature and modified requirements', () async {
    final envelope = Map<String, dynamic>.from(fixture['envelope'] as Map);
    envelope['signatureBase64'] = '';
    expect(await verify(envelope), isFalse);
    final altered = Map<String, dynamic>.from(fixture['payload'] as Map)..['requirements'] = ['firewall.new'];
    envelope['payloadBase64'] = base64Encode(utf8.encode(canonicalUpdateManifest(altered)));
    envelope['signatureBase64'] = (fixture['envelope'] as Map)['signatureBase64'];
    expect(await verify(envelope), isFalse);
  });
}
