import 'package:result_dart/result_dart.dart';

/// Reads and writes agent action bundle payloads on the local filesystem.
abstract interface class IAgentActionsBundleFileGateway {
  Future<Result<void>> writeText(String filePath, String payload);

  Future<Result<String>> readText(String filePath);
}
