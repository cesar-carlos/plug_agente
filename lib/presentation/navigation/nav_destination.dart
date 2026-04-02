import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/routes/app_routes.dart';

enum NavDestination {
  dashboard(AppRoutes.dashboard, FluentIcons.view_dashboard, AppStrings.navDashboard),
  agentProfile(AppRoutes.agentProfile, FluentIcons.contact, AppStrings.navAgentProfile),
  playground(AppRoutes.playground, FluentIcons.table, AppStrings.navPlayground),
  databaseSettings(AppRoutes.databaseSettings, FluentIcons.database, AppStrings.navDatabaseSettings),
  websocketSettings(AppRoutes.websocketSettings, FluentIcons.plug_connected, AppStrings.navWebSocketSettings),
  config(AppRoutes.config, FluentIcons.settings, AppStrings.navSettings)
  ;

  const NavDestination(this.route, this.icon, this.title);

  final String route;
  final IconData icon;
  final String title;

  static const List<NavDestination> navOrder = [
    dashboard,
    agentProfile,
    playground,
    databaseSettings,
    websocketSettings,
    config,
  ];

  static NavDestination fromIndex(int index) {
    if (index < 0 || index >= navOrder.length) return dashboard;
    return navOrder[index];
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
    if (route.startsWith(AppRoutes.agentProfile)) {
      return NavDestination.agentProfile;
    }
    return NavDestination.dashboard;
  }
}
