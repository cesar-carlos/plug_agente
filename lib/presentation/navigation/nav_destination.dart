import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

enum NavDestination {
  dashboard(AppRoutes.dashboard, FluentIcons.view_dashboard),
  agentProfile(AppRoutes.agentProfile, FluentIcons.contact),
  playground(AppRoutes.playground, FluentIcons.table),
  databaseSettings(AppRoutes.databaseSettings, FluentIcons.database),
  websocketSettings(AppRoutes.websocketSettings, FluentIcons.plug_connected),
  config(AppRoutes.config, FluentIcons.settings);

  const NavDestination(this.route, this.icon);

  final String route;
  final IconData icon;

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

extension NavDestinationLocalization on NavDestination {
  String localizedTitle(AppLocalizations l10n) {
    switch (this) {
      case NavDestination.dashboard:
        return l10n.navDashboard;
      case NavDestination.agentProfile:
        return l10n.navAgentProfile;
      case NavDestination.playground:
        return l10n.navPlayground;
      case NavDestination.databaseSettings:
        return l10n.navDatabaseSettings;
      case NavDestination.websocketSettings:
        return l10n.navWebSocketSettings;
      case NavDestination.config:
        return l10n.navSettings;
    }
  }
}
