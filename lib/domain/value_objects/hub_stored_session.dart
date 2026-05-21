import 'package:plug_agente/domain/entities/auth_token.dart';

class HubStoredSession {
  const HubStoredSession({
    this.token,
  });

  final AuthToken? token;

  bool get hasSession => token != null;
}
