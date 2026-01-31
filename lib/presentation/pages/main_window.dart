import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/routes/app_routes.dart';

class MainWindow extends StatefulWidget {
  const MainWindow({required this.child, super.key});

  final Widget child;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  NavDestination _getCurrentDestination(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return NavDestination.fromRoute(location);
  }

  void _navigateToDestination(
    BuildContext context,
    NavDestination destination,
  ) {
    context.go(destination.route);
  }

  @override
  Widget build(BuildContext context) {
    final selectedDestination = _getCurrentDestination(context);

    return NavigationView(
      appBar: const NavigationAppBar(
        title: Text(AppConstants.appName),
        automaticallyImplyLeading: false,
      ),
      pane: NavigationPane(
        selected: selectedDestination.index,
        onChanged: (index) {
          final destination = NavDestination.fromIndex(index);
          _navigateToDestination(context, destination);
        },
        displayMode: PaneDisplayMode.compact,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.view_dashboard),
            title: const Text(AppStrings.navDashboard),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.table),
            title: const Text(AppStrings.navPlayground),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text(AppStrings.navSettings),
            body: const SizedBox.shrink(),
          ),
        ],
      ),
      transitionBuilder: (child, animation) {
        return widget.child;
      },
    );
  }
}
