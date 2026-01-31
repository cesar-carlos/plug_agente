import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/routes/routes.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class PlugAgentApp extends StatelessWidget {
  const PlugAgentApp({
    this.initialRoute,
    super.key,
  });

  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return FluentApp.router(
      title: AppConstants.appName,
      theme: FluentThemeData.light(),
      darkTheme: FluentThemeData.dark(),
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FluentLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('pt'),
      ],
    );
  }
}
