import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/diagnostics_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket_config_section.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/websocket_config_form_controller.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/widgets/auth_status_feedback.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/widgets/config_error_feedback.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/widgets/connection_status_feedback.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class WebSocketSettingsPage extends StatefulWidget {
  const WebSocketSettingsPage({
    this.configId,
    super.key,
  });

  final String? configId;

  @override
  State<WebSocketSettingsPage> createState() => _WebSocketSettingsPageState();
}

class _WebSocketSettingsPageState extends State<WebSocketSettingsPage> {
  ConfigProvider? _configProvider;
  late final WebsocketConfigFormController _formController;
  late final FeatureFlags _featureFlags;
  late final PayloadSigningConfig _payloadSigningConfig;
  var _configDependenciesInitialized = false;
  final ValueNotifier<bool> _isSavingConfig = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _formController = WebsocketConfigFormController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _configProvider = context.read<ConfigProvider>()..addListener(_onConfigStateChanged);
      unawaited(_initializePage());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configDependenciesInitialized) {
      return;
    }
    _configDependenciesInitialized = true;
    _featureFlags = getIt<FeatureFlags>();
    _payloadSigningConfig =
        readOptionalGetItService<PayloadSigningConfig>() ??
        PayloadSigningConfig.empty(
          secureStorageAvailable: false,
          warnings: const <String>['payload_signing_config_not_registered'],
        );
  }

  @override
  void didUpdateWidget(WebSocketSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configId != widget.configId) {
      _formController.resetForConfig();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_initializePage());
      });
    }
  }

  Future<void> _initializePage() async {
    if (!mounted) {
      return;
    }

    if (widget.configId != null) {
      await context.read<ConfigProvider>().loadConfigById(widget.configId!);
      if (!mounted) {
        return;
      }
    }

    _initializeFormIfReady();
  }

  void _onConfigStateChanged() {
    if (!mounted) {
      return;
    }
    _initializeFormIfReady(provider: _configProvider);
  }

  void _initializeFormIfReady({ConfigProvider? provider}) {
    if (!mounted) {
      return;
    }
    final source = provider ?? context.read<ConfigProvider>();
    if (!_formController.fieldsInitialized && !source.isLoading && source.currentConfig != null) {
      _formController.initializeFromConfig(source.currentConfig);
      // Force rebuild so children that depend on the controller text pick up
      // the populated values when the provider state did not change.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigStateChanged);
    _isSavingConfig.dispose();
    _formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return MultiProvider(
      providers: [
        Provider<FeatureFlags>.value(value: _featureFlags),
        Provider<PayloadSigningConfig>.value(value: _payloadSigningConfig),
      ],
      child: AuthStatusFeedback(
        child: ConnectionStatusFeedback(
          child: ConfigErrorFeedback(
            child: ScaffoldPage(
              header: PageHeader(
                title: Text(
                  l10n.navWebSocketSettings,
                  style: context.sectionTitle,
                ),
              ),
              content: Padding(
                padding: AppLayout.pagePadding(context),
                child: AppLayout.centeredContent(
                  child: _WebSocketSettingsTabbedContent(
                    formController: _formController,
                    isSavingConfig: _isSavingConfig,
                    onSaveConfig: _saveCurrentConfig,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCurrentConfig() async {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();
    if (configProvider.error.isNotEmpty) {
      configProvider.clearError();
    }

    _isSavingConfig.value = true;
    try {
      _formController.applyToProvider(configProvider);
      final result = await configProvider.saveConfig();
      if (!mounted) {
        return;
      }
      result.fold(
        (_) => SettingsFeedback.showSuccess(
          context: context,
          title: l10n.modalTitleConfigSaved,
          message: l10n.msgConfigSavedSuccessfully,
        ),
        (failure) => SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleErrorSaving,
          message: failure.toDisplayMessage(),
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error('WebSocket config save failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isSavingConfig.value = false;
      }
    }
  }
}

/// Holds [AppFluentTabView] state so tab changes do not rebuild [ScaffoldPage]
/// or the page header.
class _WebSocketSettingsTabbedContent extends StatefulWidget {
  const _WebSocketSettingsTabbedContent({
    required this.formController,
    required this.isSavingConfig,
    required this.onSaveConfig,
  });

  final WebsocketConfigFormController formController;
  final ValueListenable<bool> isSavingConfig;
  final Future<void> Function() onSaveConfig;

  @override
  State<_WebSocketSettingsTabbedContent> createState() => _WebSocketSettingsTabbedContentState();
}

class _WebSocketSettingsTabbedContentState extends State<_WebSocketSettingsTabbedContent> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppFluentTabView(
      currentIndex: _selectedTabIndex,
      onChanged: (int index) {
        if (index == _selectedTabIndex) {
          return;
        }
        setState(() => _selectedTabIndex = index);
      },
      items: <AppFluentTabItem>[
        AppFluentTabItem(
          icon: FluentIcons.plug_connected,
          text: l10n.tabWebSocketConnection,
          body: WebSocketConfigSection(
            formController: widget.formController,
            isSavingConfig: widget.isSavingConfig,
            onSaveConfig: widget.onSaveConfig,
          ),
        ),
        AppFluentTabItem(
          icon: FluentIcons.permissions,
          text: l10n.tabClientTokenAuthorization,
          body: const _ClientTokenTabContent(),
        ),
        AppFluentTabItem(
          icon: FluentIcons.info,
          text: l10n.tabWebSocketDiagnostics,
          body: const DiagnosticsConfigSection(),
        ),
      ],
    );
  }
}

class _ClientTokenTabContent extends StatefulWidget {
  const _ClientTokenTabContent();

  @override
  State<_ClientTokenTabContent> createState() => _ClientTokenTabContentState();
}

class _ClientTokenTabContentState extends State<_ClientTokenTabContent> {
  final ScrollController _tokenListScrollController = ScrollController();
  final ScrollController _pageScrollController = ScrollController();

  @override
  void dispose() {
    _tokenListScrollController.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _pageScrollController,
      child: SingleChildScrollView(
        controller: _pageScrollController,
        child: Padding(
          padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxSettingsWidth,
            ),
            child: ClientTokenSection(
              scrollController: _tokenListScrollController,
            ),
          ),
        ),
      ),
    );
  }
}
