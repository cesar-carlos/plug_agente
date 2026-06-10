import 'package:plug_agente/domain/value_objects/hub_stored_credentials_state.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_session.dart';

class HubSessionLegacyRowBundle {
  const HubSessionLegacyRowBundle({
    required this.sessions,
    required this.credentials,
  });

  final Map<String, HubStoredSession> sessions;
  final Map<String, HubStoredCredentialsState> credentials;
}
