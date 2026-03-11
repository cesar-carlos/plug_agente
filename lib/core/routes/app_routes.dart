import 'package:go_router/go_router.dart';

class AppRoutes {
  AppRoutes._();

  static const String dashboard = '/';
  static const String playground = '/playground';
  static const String config = '/config';
  static const String configEdit = '/config/:id';

  static const String paramId = 'id';
  static const String paramTab = 'tab';
}

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

class RouteGuard {
  const RouteGuard();

  Future<bool> isAuthenticated() async {
    return true;
  }

  String get unauthenticatedRedirect => AppRoutes.dashboard;
}
