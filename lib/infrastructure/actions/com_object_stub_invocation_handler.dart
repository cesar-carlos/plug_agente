import 'package:plug_agente/infrastructure/actions/com_object_invocation_handler.dart';
import 'package:result_dart/result_dart.dart';

/// Homologation-only handler that echoes arguments without calling COM.
///
/// Register explicitly via `ComObjectInvocationBootstrap`; never enabled in production by default.
class ComObjectStubInvocationHandler extends ComObjectInvocationHandler {
  const ComObjectStubInvocationHandler();

  @override
  Future<Result<ComObjectInvocationResult>> invoke({
    required Map<String, Object?> arguments,
  }) async {
    return Success(
      ComObjectInvocationResult(
        summary: 'stub_ok',
        details: Map<String, Object?>.from(arguments),
      ),
    );
  }
}
