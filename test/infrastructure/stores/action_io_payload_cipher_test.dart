import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';

void main() {
  final key = SecretKey(List.generate(32, (i) => i));
  final cipher = ActionIoPayloadCipher(keyId: 'fixture-key', key: key);
  final context = ActionIoPayloadCipher.context(
    executionId: 'execution',
    channel: 'stdout',
    messageId: '',
    sequence: 1,
    offset: 0,
  );

  test('AES-GCM preserves exact binary content and uses distinct nonces', () async {
    for (final bytes in [
      <int>[],
      [0, 13, 10, 26, 128, 255],
      List.filled(65536, 255),
    ]) {
      final first = (await cipher.encrypt(bytes, context: context)).getOrThrow();
      final second = (await cipher.encrypt(bytes, context: context)).getOrThrow();
      expect(first.nonce, isNot(second.nonce));
      expect(first.ciphertext, hasLength(bytes.length));
      expect((await cipher.decrypt(first, expectedContext: context)).getOrThrow(), bytes);
    }
  });

  test('ciphertext, tag, nonce and authenticated context cannot be substituted', () async {
    final original = (await cipher.encrypt([0, 255], context: context)).getOrThrow();
    List<int> flip(List<int> bytes) => [...bytes]..[0] ^= 1;
    for (final changed in [
      ActionIoEncryptedPayload(
        keyId: original.keyId,
        nonce: original.nonce,
        ciphertext: flip(original.ciphertext),
        tag: original.tag,
        context: context,
      ),
      ActionIoEncryptedPayload(
        keyId: original.keyId,
        nonce: original.nonce,
        ciphertext: original.ciphertext,
        tag: flip(original.tag),
        context: context,
      ),
      ActionIoEncryptedPayload(
        keyId: original.keyId,
        nonce: flip(original.nonce),
        ciphertext: original.ciphertext,
        tag: original.tag,
        context: context,
      ),
      ActionIoEncryptedPayload(
        keyId: original.keyId,
        nonce: original.nonce,
        ciphertext: original.ciphertext,
        tag: original.tag,
        context: flip(context),
      ),
    ]) {
      expect((await cipher.decrypt(changed, expectedContext: context)).isError(), isTrue);
    }
    final otherContext = ActionIoPayloadCipher.context(
      executionId: 'other',
      channel: 'stdout',
      messageId: '',
      sequence: 1,
      offset: 0,
    );
    expect((await cipher.decrypt(original, expectedContext: otherContext)).isError(), isTrue);
  });

  test('wrong key never yields plaintext', () async {
    final encrypted = (await cipher.encrypt([1, 2], context: context)).getOrThrow();
    final wrong = ActionIoPayloadCipher(keyId: 'fixture-key', key: SecretKey(List.filled(32, 0)));
    expect((await wrong.decrypt(encrypted, expectedContext: context)).isError(), isTrue);
  });
}
