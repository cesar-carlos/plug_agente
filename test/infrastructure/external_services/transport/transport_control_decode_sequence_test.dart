import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_control_decode_sequence.dart';

void main() {
  test('keeps small synchronous effects immediate and mixed frames ordered', () async {
    final gate = Completer<dynamic>();
    final seen = <dynamic>[];
    final sequence = TransportControlDecodeSequence(
      decode: (data) => data,
      decodeAsync: (_) => gate.future,
      needsAsync: (data) => data == 'gzip',
      apply: seen.add,
      onError: (_, _) => fail('unexpected decode error'),
      sessionGeneration: () => 0,
      isConnected: () => true,
    );
    sequence.accept('none');
    expect(seen, ['none']);
    sequence.accept('gzip');
    sequence.accept('later');
    expect(seen, ['none']);
    expect(sequence.waiting, 1);
    gate.complete('gzip');
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['none', 'gzip', 'later']);
    expect(sequence.waiting, 0);
  });

  test('reset drops waiting references and isolates a new session from old completion', () async {
    var session = 0;
    var connected = true;
    final gate = Completer<dynamic>();
    final seen = <dynamic>[];
    final sequence = TransportControlDecodeSequence(
      decode: (data) => data,
      decodeAsync: (_) => gate.future,
      needsAsync: (data) => data == 'gzip',
      apply: seen.add,
      onError: (_, _) => fail('unexpected error'),
      sessionGeneration: () => session,
      isConnected: () => connected,
    );
    sequence.accept('gzip');
    sequence.accept('old');
    connected = false;
    session++;
    sequence.reset();
    expect(sequence.waiting, 0);
    connected = true;
    sequence.accept('new');
    gate.complete('old decoded');
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['new']);
  });

  test('one decode error cannot poison later control events', () async {
    final seen = <dynamic>[];
    var errors = 0;
    final sequence = TransportControlDecodeSequence(
      decode: (data) => data,
      decodeAsync: (_) async => throw StateError('bad gzip'),
      needsAsync: (data) => data == 'gzip',
      apply: seen.add,
      onError: (_, _) => errors++,
      sessionGeneration: () => 0,
      isConnected: () => true,
    );
    sequence.accept('gzip');
    sequence.accept('none');
    await Future<void>.delayed(Duration.zero);
    expect(errors, 1);
    expect(seen, ['none']);
  });
}
