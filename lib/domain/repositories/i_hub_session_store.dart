import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials_state.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_session.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IHubSessionStore {
  Future<Result<HubStoredSession>> readSession(String configId);

  Future<Result<void>> writeSessionTokens(
    String configId,
    AuthToken token,
  );

  Future<Result<void>> clearSession(String configId);

  Future<Result<HubStoredCredentialsState>> readStoredCredentials(String configId);

  Future<Result<void>> deleteAllSecrets(String configId);
}
