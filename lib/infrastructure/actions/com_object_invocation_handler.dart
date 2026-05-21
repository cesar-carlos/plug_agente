import 'package:result_dart/result_dart.dart';

/// Explicit COM invocation bound to a single ProgID and member name.
abstract class ComObjectInvocationHandler {
  const ComObjectInvocationHandler();

  Future<Result<ComObjectInvocationResult>> invoke({
    required Map<String, Object?> arguments,
  });
}

class ComObjectInvocationResult {
  const ComObjectInvocationResult({
    required this.summary,
    this.details = const <String, Object?>{},
  });

  final String summary;
  final Map<String, Object?> details;
}

typedef ComObjectInvocationKey = ({String progId, String memberName});
