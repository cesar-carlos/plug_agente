import 'dart:io';

import 'package:drift/native.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_creation_result.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';

import '../../tool/homologation/persona_chain_storage.dart' show registerChainVault;

/// Production token repository and Windows DPAPI in the owned fixture directory.
final class ActionIoCredentialFixture {
  ActionIoCredentialFixture(Directory directory)
    : database = AppDatabase(executor: NativeDatabase(File('${directory.path}/credentials.sqlite'))) {
    registerChainVault(directory);
    repository = ClientTokenRepository(
      ClientTokenLocalDataSource(database),
      secretStore: FlutterSecureTokenSecretStore(keyPrefix: 'action_io_fixture_'),
    );
  }

  final AppDatabase database;
  late final ClientTokenRepository repository;

  Future<ClientTokenCreationResult> provision(String clientId, String agentId) async {
    final created = (await CreateClientToken(repository).createWithIdentity(
      ClientTokenCreateRequest(
        clientId: clientId,
        agentId: agentId,
        name: 'Isolated action I/O',
        allTables: false,
        allViews: false,
        rules: const [],
        payload: const {
          'agent_action_scopes': [
            'agent_actions.io',
            'agent_actions.list',
            'agent_actions.run',
            'agent_actions.validate_run',
            'agent_actions.read_execution',
            'agent_actions.cancel',
          ],
        },
      ),
    )).getOrThrow();
    final stored = (await repository.getTokenSecret(created.tokenId)).getOrThrow();
    final rows = await database.select(database.clientTokenCacheTable).get();
    if (stored.tokenValue != created.tokenValue ||
        rows.isEmpty ||
        rows.any((row) => row.tokenValue != '__secure_storage__')) {
      throw StateError('Fixture token must round trip through DPAPI without plaintext in SQLite.');
    }
    return created;
  }
}
