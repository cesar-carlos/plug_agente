import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';

class GetClientTokenPolicy {
  GetClientTokenPolicy(this._resolver);

  final IAuthorizationPolicyResolver _resolver;

  Future<Result<ClientTokenPolicy>> call(String token) async {
    return _resolver.resolvePolicy(token);
  }
}
