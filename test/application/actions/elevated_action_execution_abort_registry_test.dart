import 'package:plug_agente/application/actions/elevated_action_execution_abort_registry.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionExecutionAbortRegistry', () {
    test('should complete when abort is requested for a registered execution', () async {
      final registry = ElevatedActionExecutionAbortRegistry();
      registry.register('exec-1');

      final aborted = registry.whenAborted('exec-1');
      expect(registry.requestAbort('exec-1'), isTrue);
      await expectLater(aborted, completes);
    });

    test('should return false when abort is requested for unknown execution', () {
      final registry = ElevatedActionExecutionAbortRegistry();
      expect(registry.requestAbort('missing'), isFalse);
    });
  });
}
