import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_constants.dart';
import '../../core/routes/routes.dart';

class PlugAgentApp extends StatelessWidget {
  const PlugAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp.router(
      title: AppConstants.appName,
      theme: FluentThemeData.light(),
      darkTheme: FluentThemeData.dark(),
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
    );
  }
}
