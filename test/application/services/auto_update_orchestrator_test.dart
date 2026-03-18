import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  group('AutoUpdateOrchestrator', () {
    group('isAvailable', () {
      test('should return false when supportsAutoUpdate is false', () {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        expect(orchestrator.isAvailable, isFalse);
      });

      test('should return false when supportsAutoUpdate is false (unsupported)', () {
        final capabilities = RuntimeCapabilities.unsupported(
          reasons: ['Unsupported OS'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        expect(orchestrator.isAvailable, isFalse);
      });
    });

    group('checkManual', () {
      test('should return Failure when supportsAutoUpdate is false', () async {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('not supported'));
          },
        );
      });

      test('should return Failure when supportsAutoUpdate is false (unsupported)', () async {
        final capabilities = RuntimeCapabilities.unsupported(
          reasons: ['Unsupported OS'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('not supported'));
          },
        );
      });
    });
  });
}
