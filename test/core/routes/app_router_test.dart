import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/routes/app_router.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';

void main() {
  group('app_router capabilities guard', () {
    test('should allow all routes when runtime is full', () {
      final capabilities = RuntimeCapabilities.full();

      final canAccessPlayground = isRouteAllowedForCapabilities(
        location: AppRoutes.playground,
        capabilities: capabilities,
      );

      expect(canAccessPlayground, isTrue);
    });

    test('should allow all routes when runtime is degraded', () {
      final capabilities = RuntimeCapabilities.degraded(
        reasons: ['safe mode'],
      );

      final canAccessConfig = isRouteAllowedForCapabilities(
        location: AppRoutes.config,
        capabilities: capabilities,
      );

      expect(canAccessConfig, isTrue);
    });

    test('should allow only dashboard when runtime is unsupported', () {
      final capabilities = RuntimeCapabilities.unsupported(
        reasons: ['unsupported os'],
      );

      final canAccessDashboard = isRouteAllowedForCapabilities(
        location: AppRoutes.dashboard,
        capabilities: capabilities,
      );
      final canAccessPlayground = isRouteAllowedForCapabilities(
        location: AppRoutes.playground,
        capabilities: capabilities,
      );

      expect(canAccessDashboard, isTrue);
      expect(canAccessPlayground, isFalse);
    });
  });
}
