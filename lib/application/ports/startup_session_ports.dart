import 'package:plug_agente/application/ports/i_startup_session_auth_sink.dart';
import 'package:plug_agente/application/ports/i_startup_session_config_source.dart';
import 'package:plug_agente/application/ports/i_startup_session_connection_gateway.dart';
import 'package:plug_agente/application/services/startup_session_orchestrator.dart' show StartupSessionOrchestrator;
import 'package:plug_agente/application/services/startup_session_orchestrator.dart';

/// Application-facing ports consumed by [StartupSessionOrchestrator].
class StartupSessionPorts {
  const StartupSessionPorts({
    required this.config,
    required this.auth,
    required this.connection,
  });

  final IStartupSessionConfigSource config;
  final IStartupSessionAuthSink auth;
  final IStartupSessionConnectionGateway connection;
}
