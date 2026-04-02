import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';
import 'package:provider/provider.dart';

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
    final runtimeMode = context.watch<RuntimeModeProvider>();

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
            icon: const Icon(FluentIcons.contact),
            title: const Text(AppStrings.navAgentProfile),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.table),
            title: const Text(AppStrings.navPlayground),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.database),
            title: const Text(AppStrings.navDatabaseSettings),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.plug_connected),
            title: const Text(AppStrings.navWebSocketSettings),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text(AppStrings.navSettings),
            body: const SizedBox.shrink(),
          ),
        ],
      ),
      paneBodyBuilder: (item, body) {
        return Column(
          children: [
            if (runtimeMode.isDegraded) _buildDegradedModeBanner(context),
            Expanded(
              child: AppLayout.centeredContent(child: widget.child),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDegradedModeBanner(BuildContext context) {
    final runtimeMode = context.watch<RuntimeModeProvider>();

    return InfoBar(
      title: const Text(AppStrings.mainDegradedModeTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(AppStrings.mainDegradedModeDescription),
          const SizedBox(height: AppSpacing.sm),
          ...runtimeMode.degradationReasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Text('• $reason'),
            ),
          ),
        ],
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }
}
