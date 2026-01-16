import 'package:go_router/go_router.dart';

import '../../presentation/pages/main_window.dart';
import '../../presentation/pages/dashboard_page.dart';
import '../../presentation/pages/config_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return MainWindow(child: child);
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        GoRoute(path: '/config', builder: (context, state) => const ConfigPage()),
      ],
    ),
  ],
);
