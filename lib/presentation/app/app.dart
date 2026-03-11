import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/routes/routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:provider/provider.dart';

class PlugAgentApp extends StatefulWidget {
  const PlugAgentApp({
    required this.capabilities,
    this.initialRoute,
    super.key,
  });

  final String? initialRoute;
  final RuntimeCapabilities capabilities;

  @override
  State<PlugAgentApp> createState() => _PlugAgentAppState();
}

class _PlugAgentAppState extends State<PlugAgentApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(
      capabilities: widget.capabilities,
      initialLocation: widget.initialRoute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return FluentApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
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
