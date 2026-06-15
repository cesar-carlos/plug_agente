import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:result_dart/result_dart.dart';

class _MockClientTokenRepository extends Mock implements IClientTokenRepository {}

class _MockRevokedTokenStore extends Mock implements IRevokedTokenStore {}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  test('adds revoked token to session store after successful revoke', () async {
    final repository = _MockClientTokenRepository();
    final revokedTokenStore = _MockRevokedTokenStore();
    final featureFlags = _MockFeatureFlags();

    when(() => featureFlags.enableSocketRevokedTokenInSession).thenReturn(true);
    when(() => repository.getTokenSecret('token-1')).thenAnswer(
      (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'secret-token')),
    );
    when(() => repository.revokeToken('token-1')).thenAnswer((_) async => const Success(unit));

    final useCase = RevokeClientToken(
      repository,
      revokedTokenStore: revokedTokenStore,
      featureFlags: featureFlags,
    );

    final result = await useCase.call('token-1');

    expect(result.isSuccess(), isTrue);
    verify(() => revokedTokenStore.add('secret-token')).called(1);
  });
}
