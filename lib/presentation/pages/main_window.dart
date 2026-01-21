import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';

class MainWindow extends StatefulWidget {
  final Widget child;

  const MainWindow({super.key, required this.child});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/config')) {
      return 1;
    }
    if (location.startsWith('/playground')) {
      return 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return NavigationView(
      appBar: NavigationAppBar(
        title: const Text(AppConstants.appName),
        automaticallyImplyLeading: false,
      ),
      pane: NavigationPane(
        selected: selectedIndex,
        onChanged: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/config');
              break;
            case 2:
              context.go('/playground');
              break;
          }
        },
        displayMode: PaneDisplayMode.compact,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.view_dashboard),
            title: const Text('Dashboard'),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Configurações'),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.table),
            title: const Text('Playground'),
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
