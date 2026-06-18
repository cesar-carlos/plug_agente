import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/routes/routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/widgets/auto_update_ready_banner.dart';
import 'package:provider/provider.dart';

class PlugAgentApp extends StatefulWidget {
  const PlugAgentApp({
    required this.capabilities,
    this.initialRoute,
    @visibleForTesting this.routerOverride,
    super.key,
  });

  final String? initialRoute;
  final RuntimeCapabilities capabilities;
  @visibleForTesting
  final GoRouter? routerOverride;

  @override
  State<PlugAgentApp> createState() => _PlugAgentAppState();
}

class _PlugAgentAppState extends State<PlugAgentApp> {
  static const MethodChannel _runtimeChannel = MethodChannel('plug_agente/runtime');

  late final GoRouter _router;
  final DeepLinkService _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _router =
        widget.routerOverride ??
        createAppRouter(
          capabilities: widget.capabilities,
          initialLocation: widget.initialRoute,
        );
    _runtimeChannel.setMethodCallHandler(_handleRuntimeMethodCall);
  }

  @override
  void dispose() {
    _runtimeChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleRuntimeMethodCall(MethodCall call) async {
    if (call.method != 'deliverDeepLink') {
      return;
    }

    final deepLink = call.arguments;
    if (deepLink is! String || deepLink.trim().isEmpty) {
      AppLogger.warning('Ignoring runtime deep link with invalid payload');
      return;
    }

    final route = _deepLinkService.deepLinkToRoute(deepLink);
    if (route == null) {
      AppLogger.warning('Ignoring runtime deep link because it could not be parsed: $deepLink');
      return;
    }

    final windowManager = readOptionalGetItService<IWindowManagerService>();
    if (windowManager != null) {
      try {
        await windowManager.show();
      } on Object catch (error) {
        AppLogger.warning('Failed to show window for runtime deep link', error);
      }
    }

    _router.go(route);
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
      // Stack the "update ready" banner on top of every screen so the
      // operator always sees it, regardless of which page is active.
      // The banner shrinks to zero height when there is no pending
      // downloaded update, so it has no impact on regular layouts.
      builder: (context, child) {
        return Column(
          children: [
            const AutoUpdateReadyBanner(),
            Expanded(
              child: child ?? const SizedBox.shrink(),
            ),
          ],
        );
      },
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
