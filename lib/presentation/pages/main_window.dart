import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
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
            title: Text(l10n.navDashboard),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.table),
            title: Text(l10n.navPlayground),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.database),
            title: Text(l10n.navDatabaseSettings),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.plug_connected),
            title: Text(l10n.navWebSocketSettings),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: Text(l10n.navSettings),
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
    final l10n = AppLocalizations.of(context)!;
    final runtimeMode = context.watch<RuntimeModeProvider>();

    return InfoBar(
      title: Text(l10n.mainDegradedModeTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mainDegradedModeDescription),
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
