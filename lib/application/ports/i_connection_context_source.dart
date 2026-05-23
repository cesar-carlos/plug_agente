import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Resolves tracked hub connection parameters for recovery flows.
abstract interface class IConnectionContextSource {
  HubConnectionContext? resolveConnectionContext();

  String? resolveAuthTokenForReconnect();

  String resolveActiveConfigId(String? candidateConfigId);
}
