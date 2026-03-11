import 'package:go_router/go_router.dart';

class AppRoutes {
  AppRoutes._();

  static const String dashboard = '/';
  static const String playground = '/playground';
  static const String config = '/config';
  static const String configEdit = '/config/:id';
  static const String databaseSettings = '/database-settings';
  static const String databaseSettingsEdit = '/database-settings/:id';
  static const String websocketSettings = '/websocket-settings';
  static const String websocketSettingsEdit = '/websocket-settings/:id';

  static const String paramId = 'id';
  static const String paramTab = 'tab';
}

enum NavDestination {
  dashboard,
  playground,
  databaseSettings,
  websocketSettings,
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
      case NavDestination.databaseSettings:
        return AppRoutes.databaseSettings;
      case NavDestination.websocketSettings:
        return AppRoutes.websocketSettings;
    }
  }

  static NavDestination fromIndex(int index) {
    switch (index) {
      case 1:
        return NavDestination.playground;
      case 2:
        return NavDestination.databaseSettings;
      case 3:
        return NavDestination.websocketSettings;
      case 4:
        return NavDestination.config;
      default:
        return NavDestination.dashboard;
    }
  }

  static NavDestination fromRoute(String route) {
    if (route.startsWith(AppRoutes.databaseSettings)) {
      return NavDestination.databaseSettings;
    }
    if (route.startsWith(AppRoutes.websocketSettings)) {
      return NavDestination.websocketSettings;
    }
    if (route.startsWith(AppRoutes.config)) {
      return NavDestination.config;
    }
    if (route.startsWith(AppRoutes.playground)) {
      return NavDestination.playground;
    }
    return NavDestination.dashboard;
  }
}

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

class DatabaseSettingsRoute extends GoRouteData {
  const DatabaseSettingsRoute({this.id, this.tab});

  final String? id;
  final String? tab;

  static const String $baseLocation = AppRoutes.databaseSettings;

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

class WebSocketSettingsRoute extends GoRouteData {
  const WebSocketSettingsRoute({this.id, this.tab});

  final String? id;
  final String? tab;

  static const String $baseLocation = AppRoutes.websocketSettings;

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

class RouteGuard {
  const RouteGuard();

  Future<bool> isAuthenticated() async {
    return true;
  }

  String get unauthenticatedRedirect => AppRoutes.dashboard;
}
