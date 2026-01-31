import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/pages/dashboard_page.dart';
import 'package:plug_agente/presentation/pages/main_window.dart';
import 'package:plug_agente/presentation/pages/playground_page.dart';

/// Route guard instance.
///
/// Used for protecting routes with authentication checks.
const _routeGuard = RouteGuard();

/// Application router configuration.
///
/// Features:
/// - Type-safe routes with GoRouteData
/// - Route guards for authentication
/// - Deep linking support for desktop
/// - Query parameters support
/// - Debug logging for development
final appRouter = GoRouter(
  debugLogDiagnostics: kDebugMode,
  redirect: _handleRedirect,
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
            // Extract query parameters if needed
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
            return ConfigPage(configId: id, initialTab: tab);
          },
        ),
        GoRoute(
          path: AppRoutes.config,
          name: 'config',
          builder: (context, state) {
            final tab = state.uri.queryParameters[AppRoutes.paramTab];
            return ConfigPage(initialTab: tab);
          },
        ),
      ],
    ),
  ],
);

/// Redirect handler for route guards.
///
/// Called before navigating to a route. Can redirect to a different
/// location based on authentication status or other conditions.
Future<String?> _handleRedirect(
  BuildContext context,
  GoRouterState state,
) async {
  // Check if route requires authentication
  final isAuthenticated = await _routeGuard.isAuthenticated();

  // If not authenticated, redirect to unauthenticated location
  if (!isAuthenticated) {
    return _routeGuard.unauthenticatedRedirect;
  }

  // No redirect needed
  return null;
}
