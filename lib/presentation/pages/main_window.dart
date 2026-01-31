import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';

class MainWindow extends StatefulWidget {
  const MainWindow({required this.child, super.key});
  final Widget child;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/config')) {
      return 2;
    }
    if (location.startsWith('/playground')) {
      return 1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return NavigationView(
      appBar: const NavigationAppBar(
        title: Text(AppConstants.appName),
        automaticallyImplyLeading: false,
      ),
      pane: NavigationPane(
        selected: selectedIndex,
        onChanged: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/playground');
            case 2:
              context.go('/config');
          }
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
      // Usando transitionBuilder para exibir a página atual do Router
      // Isso evita o erro de assert do content vs pane, e garante que o widget.child (GoRouter) seja exibido.
      transitionBuilder: (child, animation) {
        return widget.child;
      },
    );
  }
}
