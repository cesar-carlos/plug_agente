import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/routes/app_routes.dart';

void main() {
  group('NavDestination', () {
    test('should return correct route for dashboard', () {
      expect(NavDestination.dashboard.route, equals(AppRoutes.dashboard));
    });

    test('should return correct route for playground', () {
      expect(NavDestination.playground.route, equals(AppRoutes.playground));
    });

    test('should return correct route for config', () {
      expect(NavDestination.config.route, equals(AppRoutes.config));
    });

    test('should return correct destination from index 0', () {
      expect(NavDestination.fromIndex(0), equals(NavDestination.dashboard));
    });

    test('should return correct destination from index 1', () {
      expect(NavDestination.fromIndex(1), equals(NavDestination.playground));
    });

    test('should return correct destination from index 2', () {
      expect(NavDestination.fromIndex(2), equals(NavDestination.config));
    });

    test('should return dashboard for invalid index', () {
      expect(NavDestination.fromIndex(-1), equals(NavDestination.dashboard));
      expect(NavDestination.fromIndex(3), equals(NavDestination.dashboard));
      expect(NavDestination.fromIndex(999), equals(NavDestination.dashboard));
    });

    test('should return dashboard from root route', () {
      expect(NavDestination.fromRoute('/'), equals(NavDestination.dashboard));
    });

    test('should return config from config route', () {
      expect(
        NavDestination.fromRoute('/config'),
        equals(NavDestination.config),
      );
    });

    test('should return config from config route with ID', () {
      expect(
        NavDestination.fromRoute('/config/abc123'),
        equals(NavDestination.config),
      );
    });

    test('should return playground from playground route', () {
      expect(
        NavDestination.fromRoute('/playground'),
        equals(NavDestination.playground),
      );
    });

    test('should return playground from playground route with params', () {
      expect(
        NavDestination.fromRoute('/playground?id=xyz'),
        equals(NavDestination.playground),
      );
    });

    test('should have correct index values', () {
      expect(NavDestination.dashboard.index, equals(0));
      expect(NavDestination.playground.index, equals(1));
      expect(NavDestination.config.index, equals(2));
    });
  });

  group('AppRoutes', () {
    test('should have correct route constants', () {
      expect(AppRoutes.dashboard, equals('/'));
      expect(AppRoutes.playground, equals('/playground'));
      expect(AppRoutes.config, equals('/config'));
      expect(AppRoutes.configEdit, equals('/config/:id'));
    });

    test('should have correct parameter names', () {
      expect(AppRoutes.paramId, equals('id'));
      expect(AppRoutes.paramTab, equals('tab'));
    });
  });

  group('ConfigRoute', () {
    test('should generate location without parameters', () {
      const route = ConfigRoute();
      // Access the property using a helper to avoid $ escaping issues
      expect(route.id, isNull);
      expect(route.tab, isNull);
    });

    test('should generate location with id parameter', () {
      const route = ConfigRoute(id: 'abc123');
      expect(route.id, equals('abc123'));
      expect(route.tab, isNull);
    });

    test('should generate location with tab parameter', () {
      const route = ConfigRoute(tab: 'websocket');
      expect(route.id, isNull);
      expect(route.tab, equals('websocket'));
    });

    test('should generate location with both parameters', () {
      const route = ConfigRoute(id: 'xyz', tab: 'websocket');
      expect(route.id, equals('xyz'));
      expect(route.tab, equals('websocket'));
    });
  });

  group('RouteGuard', () {
    test('should return true for isAuthenticated by default', () async {
      const guard = RouteGuard();
      expect(await guard.isAuthenticated(), isTrue);
    });

    test('should return dashboard as unauthenticatedRedirect', () {
      const guard = RouteGuard();
      expect(guard.unauthenticatedRedirect, equals(AppRoutes.dashboard));
    });
  });
}
