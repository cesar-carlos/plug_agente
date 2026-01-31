import 'package:go_router/go_router.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/pages/dashboard_page.dart';
import 'package:plug_agente/presentation/pages/main_window.dart';
import 'package:plug_agente/presentation/pages/playground_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return MainWindow(child: child);
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        GoRoute(
          path: '/config',
          builder: (context, state) => const ConfigPage(),
        ),
        GoRoute(
          path: '/playground',
          builder: (context, state) => const PlaygroundPage(),
        ),
      ],
    ),
  ],
);
