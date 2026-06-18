import 'package:plug_agente/domain/entities/auth_token.dart';

/// Auth side-effects required while bootstrapping a startup session.
abstract interface class IStartupSessionAuthSink {
  void restoreToken(
    AuthToken token, {
    String? configId,
    bool silent = false,
  });

  void setRecoveryError(String message);
}
