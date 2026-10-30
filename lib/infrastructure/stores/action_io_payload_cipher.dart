import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoEncryptedPayload {
  ActionIoEncryptedPayload({
    required this.keyId,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> tag,
    required List<int> context,
  }) : nonce = Uint8List.fromList(nonce).asUnmodifiableView(),
       ciphertext = Uint8List.fromList(ciphertext).asUnmodifiableView(),
       tag = Uint8List.fromList(tag).asUnmodifiableView(),
       context = Uint8List.fromList(context).asUnmodifiableView();

  final String keyId;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;
  final Uint8List context;
}

final class ActionIoPayloadCipher {
  ActionIoPayloadCipher({required this.keyId, required SecretKey key}) : _key = key;

  final String keyId;
  final SecretKey _key;
  final AesGcm _algorithm = AesGcm.with256bits();

  static Uint8List context({
    required String executionId,
    required String channel,
    required String messageId,
    required int sequence,
    required int offset,
  }) => Uint8List.fromList(
    utf8.encode(jsonEncode([1, executionId, channel, messageId, sequence, offset])),
  );

  Future<Result<ActionIoEncryptedPayload>> encrypt(List<int> bytes, {required List<int> context}) async {
    try {
      final box = await _algorithm.encrypt(bytes, secretKey: _key, aad: context);
      return Success(
        ActionIoEncryptedPayload(
          keyId: keyId,
          nonce: box.nonce,
          ciphertext: box.cipherText,
          tag: box.mac.bytes,
          context: context,
        ),
      );
    } on Exception catch (error) {
      return Failure(_failure('ACTION_IO_KEY_UNAVAILABLE', error));
    }
  }

  Future<Result<Uint8List>> decrypt(ActionIoEncryptedPayload payload, {required List<int> expectedContext}) async {
    if (payload.keyId != keyId) return Failure(_failure('ACTION_IO_KEY_UNAVAILABLE'));
    if (payload.nonce.length != 12 || payload.tag.length != 16 || !_equal(payload.context, expectedContext)) {
      return Failure(_failure('ACTION_IO_INTEGRITY_FAILED'));
    }
    try {
      final bytes = await _algorithm.decrypt(
        SecretBox(payload.ciphertext, nonce: payload.nonce, mac: Mac(payload.tag)),
        secretKey: _key,
        aad: expectedContext,
      );
      return Success(Uint8List.fromList(bytes));
    } on Exception catch (error) {
      return Failure(_failure('ACTION_IO_INTEGRITY_FAILED', error));
    }
  }

  bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  ActionRuntimeFailure _failure(String code, [Object? error]) => ActionRuntimeFailure.withContext(
    message: 'The encrypted I/O payload is unavailable or invalid.',
    code: code,
    context: {'retryable': false, if (error != null) 'cause_type': error.runtimeType.toString()},
  );
}
