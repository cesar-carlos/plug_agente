import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';

final class ComObjectInvocationDiagnostics implements IComObjectInvocationDiagnostics {
  ComObjectInvocationDiagnostics(this._registry);

  final ComObjectInvocationRegistry _registry;

  @override
  int get registeredHandlerCount => _registry.registeredInvocations.length;
}
