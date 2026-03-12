import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAuthorizationPolicyResolver {
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token);
}
