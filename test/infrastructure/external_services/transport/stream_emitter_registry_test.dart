import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/stream_emitter_registry.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';

BackpressureStreamEmitter _emitter() {
  return BackpressureStreamEmitter(
    emit: (_, _) async {},
    onRegister: (_, _) {},
    onUnregister: (_) {},
  );
}

void main() {
  group('StreamEmitterRegistry effective cap', () {
    test('uses negotiated cap when below hard ceiling', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 4,
      );

      expect(registry.effectiveCap, 4);
    });

    test('clamps to hard ceiling when negotiated exceeds it', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 8,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 1024,
      );

      expect(registry.effectiveCap, 8);
    });

    test('falls back to hard ceiling when negotiated is non-positive', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 16,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 0,
      );

      expect(registry.effectiveCap, 16);
    });

    test('default capProvider returns hard ceiling', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 32,
        idleTtl: const Duration(minutes: 5),
      );

      expect(registry.effectiveCap, 32);
    });
  });

  group('StreamEmitterRegistry tryRegister', () {
    test('accepts emitters up to the negotiated cap', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 3,
      );

      expect(registry.tryRegister('s1', _emitter()), isTrue);
      expect(registry.tryRegister('s2', _emitter()), isTrue);
      expect(registry.tryRegister('s3', _emitter()), isTrue);
      expect(registry.tryRegister('s4', _emitter()), isFalse);
      expect(registry.activeCount, 3);
    });

    test('replacing an existing stream id does not consume a new slot', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 2,
      );

      expect(registry.tryRegister('s1', _emitter()), isTrue);
      expect(registry.tryRegister('s2', _emitter()), isTrue);
      // Re-register an existing id; should still be allowed even at cap.
      expect(registry.tryRegister('s1', _emitter()), isTrue);
      expect(registry.activeCount, 2);
    });

    test('unregister releases a slot', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 1,
      );

      expect(registry.tryRegister('s1', _emitter()), isTrue);
      expect(registry.tryRegister('s2', _emitter()), isFalse);

      registry.unregister('s1');
      expect(registry.tryRegister('s2', _emitter()), isTrue);
    });

    test('dispose cancels all timers and clears emitters', () {
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => 4,
      );
      registry.tryRegister('s1', _emitter());
      registry.tryRegister('s2', _emitter());

      registry.dispose();
      expect(registry.activeCount, 0);
    });

    test('cap can grow dynamically when negotiated value increases', () {
      var cap = 1;
      final registry = StreamEmitterRegistry(
        hardCeiling: 64,
        idleTtl: const Duration(minutes: 5),
        capProvider: () => cap,
      );

      expect(registry.tryRegister('s1', _emitter()), isTrue);
      expect(registry.tryRegister('s2', _emitter()), isFalse);

      cap = 4;
      expect(registry.tryRegister('s2', _emitter()), isTrue);
      expect(registry.tryRegister('s3', _emitter()), isTrue);
    });
  });
}
