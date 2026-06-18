import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/presentation/adapters/hub_recovery_auth_bridge.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';

/// Binds [HubRecoveryAuthBridge] to hub connection recovery and token renewal.
///
/// Must run as soon as [AuthProvider] and [ConnectionProvider] exist so
/// authenticated HTTP can renew tokens before deferred bootstrap work.
void wireHubRecoveryAuthBridge({
  required AuthProvider authProvider,
  required ConnectionProvider connectionProvider,
  HubSessionCoordinator? sessionCoordinator,
}) {
  connectionProvider.setAuthProvider(authProvider);

  final bridge = HubRecoveryAuthBridge(
    sessionCoordinator: sessionCoordinator ?? getIt<HubSessionCoordinator>(),
    authProvider: authProvider,
  );
  connectionProvider.setHubRecoveryAuthBridge(bridge);
}
