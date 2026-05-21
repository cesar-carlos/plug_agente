import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:plug_agente/infrastructure/actions/com_object_stub_invocation_handler.dart';

void main() {
  group('ComObjectInvocationDiagnostics', () {
    test('should report registered handler count from registry', () {
      final registry = ComObjectInvocationRegistry(const [
        RegisteredComObjectInvocation(
          progId: 'Test.Prog',
          memberName: 'Run',
          handler: ComObjectStubInvocationHandler(),
        ),
      ]);
      final diagnostics = ComObjectInvocationDiagnostics(registry);

      expect(diagnostics.registeredHandlerCount, 1);
    });
  });
}
