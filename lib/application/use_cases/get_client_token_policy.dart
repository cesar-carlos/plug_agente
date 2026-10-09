import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/services/client_token_lifetime_validator.dart';
import 'package:result_dart/result_dart.dart';

class GetClientTokenPolicy {
  GetClientTokenPolicy(this._resolver, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final IAuthorizationPolicyResolver _resolver;
  final DateTime Function() _now;

  Future<Result<ClientTokenPolicy>> call(String token) async {
    final result = await _resolver.resolvePolicy(token);
    return result.fold((policy) => ClientTokenLifetimeValidator.validate(policy, now: _now()), Failure.new);
  }
}
