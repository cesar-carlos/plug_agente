import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/presentation/pages/agent_profile_page.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/pages/dashboard_page.dart';
import 'package:plug_agente/presentation/pages/database_settings_page.dart';
import 'package:plug_agente/presentation/pages/main_window.dart';
import 'package:plug_agente/presentation/pages/playground_page.dart';
import 'package:plug_agente/presentation/pages/websocket_settings_page.dart';

/// Route guard instance.
///
/// Used for protecting routes with authentication checks.
const _routeGuard = RouteGuard();

/// Application router factory.
GoRouter createAppRouter({
  required RuntimeCapabilities capabilities,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppRoutes.dashboard,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) => _handleRedirect(context, state, capabilities),
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return MainWindow(child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: AppRoutes.playground,
            name: 'playground',
            builder: (context, state) {
              final configId = state.uri.queryParameters[AppRoutes.paramId];
              return PlaygroundPage(configId: configId);
            },
          ),
          GoRoute(
            path: '${AppRoutes.config}/:id',
            name: 'configEdit',
            builder: (context, state) {
              final id = state.pathParameters[AppRoutes.paramId] ?? '';
              final tab = state.uri.queryParameters[AppRoutes.paramTab];
              if (tab == 'websocket') {
                return WebSocketSettingsPage(configId: id);
              }
              if (tab == 'database' || tab == 'advanced') {
                return DatabaseSettingsPage(configId: id, initialTab: tab);
              }
              return const ConfigPage();
            },
          ),
          GoRoute(
            path: AppRoutes.config,
            name: 'config',
            builder: (context, state) {
              final tab = state.uri.queryParameters[AppRoutes.paramTab];
              if (tab == 'websocket') {
                return const WebSocketSettingsPage();
              }
              if (tab == 'database' || tab == 'advanced') {
                return DatabaseSettingsPage(initialTab: tab);
              }
              return const ConfigPage();
            },
          ),
          GoRoute(
            path: '${AppRoutes.agentProfile}/:id',
            name: 'agentProfileEdit',
            builder: (context, state) {
              final id = state.pathParameters[AppRoutes.paramId] ?? '';
              return AgentProfilePage(
                configId: id,
                pushAgentProfileToHub: getIt<PushAgentProfileToHub>(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.agentProfile,
            name: 'agentProfile',
            builder: (context, state) {
              return AgentProfilePage(
                pushAgentProfileToHub: getIt<PushAgentProfileToHub>(),
              );
            },
          ),
          GoRoute(
            path: '${AppRoutes.databaseSettings}/:id',
            name: 'databaseSettingsEdit',
            builder: (context, state) {
              final id = state.pathParameters[AppRoutes.paramId] ?? '';
              final tab = state.uri.queryParameters[AppRoutes.paramTab];
              return DatabaseSettingsPage(configId: id, initialTab: tab);
            },
          ),
          GoRoute(
            path: AppRoutes.databaseSettings,
            name: 'databaseSettings',
            builder: (context, state) {
              final tab = state.uri.queryParameters[AppRoutes.paramTab];
              return DatabaseSettingsPage(initialTab: tab);
            },
          ),
          GoRoute(
            path: '${AppRoutes.websocketSettings}/:id',
            name: 'websocketSettingsEdit',
            builder: (context, state) {
              final id = state.pathParameters[AppRoutes.paramId] ?? '';
              return WebSocketSettingsPage(configId: id);
            },
          ),
          GoRoute(
            path: AppRoutes.websocketSettings,
            name: 'websocketSettings',
            builder: (context, state) {
              return const WebSocketSettingsPage();
            },
          ),
        ],
      ),
    ],
  );
}

bool isRouteAllowedForCapabilities({
  required String location,
  required RuntimeCapabilities capabilities,
}) {
  if (capabilities.isUnsupported) {
    return location == AppRoutes.dashboard;
  }
  return true;
}

/// Redirect handler for route guards.
///
/// Called before navigating to a route. Can redirect to a different
/// location based on authentication status or other conditions.
Future<String?> _handleRedirect(
  BuildContext context,
  GoRouterState state,
  RuntimeCapabilities capabilities,
) async {
  // Check if route requires authentication
  final isAuthenticated = await _routeGuard.isAuthenticated();

  // If not authenticated, redirect to unauthenticated location
  if (!isAuthenticated) {
    return _routeGuard.unauthenticatedRedirect;
  }

  if (!isRouteAllowedForCapabilities(
    location: state.matchedLocation,
    capabilities: capabilities,
  )) {
    return AppRoutes.dashboard;
  }

  // No redirect needed
  return null;
}
