import 'package:go_router/go_router.dart';

/// Application route constants.
///
/// Centralizes all route paths to avoid hardcoded strings
/// and enable type-safe navigation.
class AppRoutes {
  AppRoutes._();

  static const String dashboard = '/';
  static const String playground = '/playground';
  static const String config = '/config';
  static const String configEdit = '/config/:id';

  /// Query parameter names
  static const String paramId = 'id';
  static const String paramTab = 'tab';
}

/// Navigation destinations for the main window.
///
/// Maps to the navigation pane items and their corresponding routes.
enum NavDestination {
  dashboard,
  playground,
  config
  ;

  String get route {
    switch (this) {
      case NavDestination.dashboard:
        return AppRoutes.dashboard;
      case NavDestination.playground:
        return AppRoutes.playground;
      case NavDestination.config:
        return AppRoutes.config;
    }
  }

  static NavDestination fromIndex(int index) {
    switch (index) {
      case 1:
        return NavDestination.playground;
      case 2:
        return NavDestination.config;
      default:
        return NavDestination.dashboard;
    }
  }

  static NavDestination fromRoute(String route) {
    if (route.startsWith(AppRoutes.config)) {
      return NavDestination.config;
    }
    if (route.startsWith(AppRoutes.playground)) {
      return NavDestination.playground;
    }
    return NavDestination.dashboard;
  }
}

/// Type-safe route data classes using GoRouteData.
///
/// Provides compile-time safety for navigation and parameters.
class DashboardRoute extends GoRouteData {
  const DashboardRoute();

  static const String $location = AppRoutes.dashboard;
}

class PlaygroundRoute extends GoRouteData {
  const PlaygroundRoute();

  static const String $location = AppRoutes.playground;
}

class ConfigRoute extends GoRouteData {
  const ConfigRoute({this.id, this.tab});

  final String? id;
  final String? tab;

  static const String $baseLocation = AppRoutes.config;

  String get $location {
    final buf = StringBuffer($baseLocation);
    if (id != null) {
      buf.write('/$id');
    }
    if (tab != null) {
      buf.write('?tab=$tab');
    }
    return buf.toString();
  }
}

/// Route guards for protecting routes.
///
/// Implements authentication and authorization checks.
class RouteGuard {
  const RouteGuard();

  /// Checks if user is authenticated.
  ///
  /// Returns `true` if the user can access the route, `false` otherwise.
  /// Override this method to implement custom authentication logic.
  Future<bool> isAuthenticated() async {
    // TODO: Implement actual authentication check
    // For now, always return true to allow access
    // In the future, check AuthProvider or token storage
    return true;
  }

  /// Returns the redirect location if user is not authenticated.
  ///
  /// Override to specify a custom login route.
  String get unauthenticatedRedirect {
    // For now, redirect to dashboard
    // In the future, redirect to a login page
    return AppRoutes.dashboard;
  }
}
