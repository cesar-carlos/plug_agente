import 'package:result_dart/result_dart.dart';

/// Resolves `${secret:name}` placeholders at action execution time.
abstract interface class IAgentActionSecretPlaceholderResolver {
  Future<Result<String>> resolveText({
    required String text,
    required String actionId,
    String phase = 'execution_preflight',
  });
}
