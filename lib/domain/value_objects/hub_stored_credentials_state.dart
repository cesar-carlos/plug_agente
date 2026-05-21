import 'package:plug_agente/domain/value_objects/hub_stored_credentials.dart';

class HubStoredCredentialsState {
  const HubStoredCredentialsState({
    this.credentials,
  });

  final HubStoredCredentials? credentials;

  bool get hasCredentials => credentials != null;
}
