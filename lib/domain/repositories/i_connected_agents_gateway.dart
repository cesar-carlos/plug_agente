import 'package:result_dart/result_dart.dart';

abstract class IConnectedAgentsGateway {
  Future<Result<String>> fetchAgentsList({
    required String serverUrl,
    required String accessToken,
    String? configId,
  });
}
