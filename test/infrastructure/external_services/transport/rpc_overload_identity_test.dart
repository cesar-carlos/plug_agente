import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_wire_payload.dart';
import 'package:result_dart/result_dart.dart';

class _Codec extends Mock implements PayloadFrameCodec {}

void main() {
  test('overload identity awaits heavy decode and preserves numeric id and method', () async {
    final codec = _Codec();
    final payload = <String, dynamic>{'cmp': 'gzip', 'originalSize': 100000};
    final gate = Completer<Result<dynamic>>();
    when(() => codec.looksLikePayloadFrame(payload)).thenReturn(true);
    when(() => codec.decodeIncomingAsync(payload, sourceEvent: 'rpc:request')).thenAnswer((_) => gate.future);
    final pending = extractBestEffortRequestIdentityForRateLimitAsync(payload, frameCodec: codec);
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete(const Success({'id': 42, 'method': 'sql.execute'}));
    final identity = await pending;
    expect(identity.id, 42);
    expect(identity.method, 'sql.execute');
    verify(() => codec.decodeIncomingAsync(payload, sourceEvent: 'rpc:request')).called(1);
  });

  test('a raw map with frame-looking extensions retains the existing overload identity', () async {
    final codec = _Codec();
    final payload = <String, dynamic>{'id': 42, 'method': 'sql.execute', 'cmp': 'gzip'};
    when(() => codec.looksLikePayloadFrame(payload)).thenReturn(false);
    final identity = await extractBestEffortRequestIdentityForRateLimitAsync(payload, frameCodec: codec);
    expect(identity.id, 42);
    expect(identity.method, 'sql.execute');
    verifyNever(() => codec.decodeIncomingAsync(payload, sourceEvent: 'rpc:request'));
  });
}
