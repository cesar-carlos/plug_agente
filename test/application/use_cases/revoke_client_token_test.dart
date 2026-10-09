import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

import '../../helpers/memory_token_secret_store.dart';

class _MockRevokedTokenStore extends Mock implements IRevokedTokenStore {}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  for (final enabled in [true, false]) {
    test('records persisted revocation hash without reading secrets when enabled=$enabled', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final source = ClientTokenLocalDataSource(database);
      final revokedTokenStore = _MockRevokedTokenStore();
      final featureFlags = _MockFeatureFlags();
      final secrets = MemoryTokenSecretStore();
      when(() => featureFlags.enableSocketRevokedTokenInSession).thenReturn(enabled);
      final repository = ClientTokenRepository(
        source,
        secretStore: secrets,
        revokedTokenStore: revokedTokenStore,
        featureFlags: featureFlags,
      );
      final token = (await repository.createToken(
        const ClientTokenCreateRequest(
          clientId: 'client',
          allTables: true,
          allViews: false,
          rules: [],
        ),
      )).getOrThrow();
      final id = (await source.listTokens()).single.id;
      secrets.available = false;
      secrets.reads = 0;

      expect((await RevokeClientToken(repository)(id)).isSuccess(), isTrue);
      expect(secrets.reads, 0);
      if (enabled) {
        verify(() => revokedTokenStore.addCredentialHash(hashClientCredentialToken(token))).called(1);
      } else {
        verifyNever(() => revokedTokenStore.addCredentialHash(any()));
      }
      verifyNever(() => revokedTokenStore.add(any()));
    });
  }
}
