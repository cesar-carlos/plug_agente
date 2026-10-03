import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/stream_emitter_registry.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';

void main() {
  setUp(() => AppLogger.attachStructuredSink(_QuietLogSink()));
  tearDown(AppLogger.detachStructuredSink);
  test('expiry invalidates the producer and releases pending chunks', () {
    fakeAsync((clock) {
      final registry = StreamEmitterRegistry(hardCeiling: 1, idleTtl: const Duration(seconds: 1));
      final emitter = BackpressureStreamEmitter(
        initialSendCredit: 0,
        emit: (_, _) async => true,
        onRegister: registry.tryRegister,
        onUnregister: registry.unregister,
      );
      emitter.emitChunk(RpcStreamChunk(streamId: 's', requestId: 'r', chunkIndex: 0, rows: const []));
      clock.flushMicrotasks();
      expect(emitter.queuedChunks, 1);
      clock.elapse(const Duration(seconds: 1));
      expect(emitter.isFaulted, isTrue);
      expect(emitter.queuedChunks, 0);
      expect(registry.activeCount, 0);
      expect(registry.activeTimers, 0);
      expect(registry.expiredEmitters, 1);
      expect(registry.diagnostics, {
        'active_emitters': 0,
        'active_timers': 0,
        'expired_emitters': 1,
        'queued_chunks': 0,
        'queue_peak': 1,
      });
      registry.dispose();
    });
  });

  test('stale unregister cannot remove a replacement emitter', () {
    fakeAsync((clock) {
      final registry = StreamEmitterRegistry(hardCeiling: 1, idleTtl: const Duration(seconds: 1));
      BackpressureStreamEmitter make() => BackpressureStreamEmitter(
        emit: (_, _) async => true,
        onRegister: registry.tryRegister,
        onUnregister: registry.unregister,
      );
      final old = make();
      final current = make();
      registry.tryRegister('s', old);
      clock.elapse(const Duration(milliseconds: 500));
      registry.tryRegister('s', current);
      expect(old.isFaulted, isTrue);
      registry.unregister('s', emitter: old);
      clock.elapse(const Duration(milliseconds: 500));
      expect(registry.get('s'), same(current));
      registry.dispose();
    });
  });

  test('twenty thousand registration cycles retain no timer or emitter', () {
    fakeAsync((clock) {
      final registry = StreamEmitterRegistry(hardCeiling: 1, idleTtl: const Duration(seconds: 1));
      for (var i = 0; i < 20000; i++) {
        final emitter = BackpressureStreamEmitter(
          emit: (_, _) async => true,
          onRegister: registry.tryRegister,
          onUnregister: registry.unregister,
        );
        registry.tryRegister('s', emitter);
        clock.elapse(const Duration(seconds: 1));
      }
      expect(registry.activeCount, 0);
      expect(registry.activeTimers, 0);
      expect(registry.diagnostics['expired_emitters'], 20000);
      registry.dispose();
    });
  });
}

class _QuietLogSink implements IStructuredLogSink {
  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {}
}
