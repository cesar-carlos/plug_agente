import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/diagnostics_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket_config_section.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
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
  AuthStatus? _previousAuthStatus;
  String _previousAuthError = '';
  ConnectionStatus? _previousConnectionStatus;
  String _previousConnectionError = '';
  String _previousConfigError = '';
  AuthProvider? _authProvider;
  ConnectionProvider? _connectionProvider;
  ConfigProvider? _configProvider;
  late final ConfigFormController _formController;

  @override
  void initState() {
    super.initState();
    _formController = ConfigFormController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.configId != null) {
        _loadConfig(widget.configId!);
      }
      _checkAndInitializeFields();
      _setupAuthListener();
      _setupConnectionListener();
      _setupConfigListener();
    });
  }

  @override
  void didUpdateWidget(WebSocketSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configId != widget.configId) {
      _formController.resetForConfig();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.configId != null) {
          _loadConfig(widget.configId!);
        }
        _checkAndInitializeFields();
      });
    }
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  void _setupAuthListener() {
    _authProvider = context.read<AuthProvider>();
    _previousAuthStatus = _authProvider!.status;
    _previousAuthError = _authProvider!.error;
    _authProvider!.addListener(_onAuthStateChanged);
  }

  void _setupConnectionListener() {
    _connectionProvider = context.read<ConnectionProvider>();
    _previousConnectionStatus = _connectionProvider!.status;
    _previousConnectionError = _connectionProvider!.error;
    _connectionProvider!.addListener(_onConnectionStateChanged);
  }

  void _setupConfigListener() {
    _configProvider = context.read<ConfigProvider>();
    _previousConfigError = _configProvider!.error;
    _configProvider!.addListener(_onConfigStateChanged);
  }

  void _onAuthStateChanged() {
    if (!mounted) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentStatus = authProvider.status;
    final currentError = authProvider.error;

    if (_previousAuthStatus != AuthStatus.authenticated &&
        currentStatus == AuthStatus.authenticated &&
        currentError.isEmpty) {
      _showSuccessModal();
    }

    if (currentError.isNotEmpty && currentError != _previousAuthError) {
      _showErrorModal(currentError);
    }

    _previousAuthStatus = currentStatus;
    _previousAuthError = currentError;
  }

  void _onConnectionStateChanged() {
    if (!mounted) {
      return;
    }

    final connectionProvider = context.read<ConnectionProvider>();
    final currentStatus = connectionProvider.status;
    final currentError = connectionProvider.error;

    if (_previousConnectionStatus != ConnectionStatus.connected && currentStatus == ConnectionStatus.connected) {
      _showConnectionSuccessModal();
    }

    if (currentError.isNotEmpty && currentError != _previousConnectionError) {
      _showConnectionErrorModal(currentError);
    }

    _previousConnectionStatus = currentStatus;
    _previousConnectionError = currentError;
  }

  void _onConfigStateChanged() {
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
    final currentError = configProvider.error;

    if (currentError.isNotEmpty && currentError != _previousConfigError) {
      _showConfigErrorModal(currentError);
    }

    _previousConfigError = currentError;
  }

  void _showSuccessModal() {
    final l10n = AppLocalizations.of(context)!;
    _showSuccessMessage(
      title: l10n.modalTitleSuccess,
      message: l10n.msgAuthenticatedSuccessfully,
    );
  }

  void _showConnectionSuccessModal() {
    final l10n = AppLocalizations.of(context)!;
    _showSuccessMessage(
      title: l10n.modalTitleConnectionEstablished,
      message: l10n.msgWebSocketConnectedSuccessfully,
    );
  }

  void _showSuccessMessage({
    required String title,
    required String message,
  }) {
    SettingsFeedback.showSuccess(
      context: context,
      title: title,
      message: message,
    );
  }

  void _showErrorWithClear({
    required String title,
    required String message,
    required VoidCallback onClear,
  }) {
    SettingsFeedback.showError(
      context: context,
      title: title,
      message: message,
      onConfirm: onClear,
    );
  }

  void _showConnectionErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    _showErrorWithClear(
      title: l10n.modalTitleConnectionError,
      message: error,
      onClear: () {
        context.read<ConnectionProvider>().clearError();
      },
    );
  }

  void _showConfigErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    _showErrorWithClear(
      title: l10n.modalTitleConfigError,
      message: error,
      onClear: () {
        context.read<ConfigProvider>().clearError();
      },
    );
  }

  void _showErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    _showErrorWithClear(
      title: l10n.modalTitleAuthError,
      message: error,
      onClear: () {
        context.read<AuthProvider>().clearError();
      },
    );
  }

  void _checkAndInitializeFields() {
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
    if (!_formController.fieldsInitialized && !configProvider.isLoading && configProvider.currentConfig != null) {
      _formController.initializeFromConfig(configProvider.currentConfig);
    } else if (configProvider.isLoading) {
      unawaited(
        Future.delayed(
          AppConstants.formTransitionDelay,
          _checkAndInitializeFields,
        ).catchError(
          (Object e, StackTrace? s) => AppLogger.warning(
            'Form field initialization check failed',
            e,
            s,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthStateChanged);
    _connectionProvider?.removeListener(_onConnectionStateChanged);
    _configProvider?.removeListener(_onConfigStateChanged);
    _formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();

    return ScaffoldPage(
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
            configProvider: configProvider,
          ),
        ),
      ),
    );
  }
}

/// Holds [AppFluentTabView] state so tab changes do not rebuild [ScaffoldPage]
/// or the page header.
class _WebSocketSettingsTabbedContent extends StatefulWidget {
  const _WebSocketSettingsTabbedContent({
    required this.formController,
    required this.configProvider,
  });

  final ConfigFormController formController;
  final ConfigProvider configProvider;

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
          body: ListenableBuilder(
            listenable: widget.configProvider,
            builder: (BuildContext context, Widget? _) {
              return WebSocketConfigSection(
                formController: widget.formController,
                configProvider: widget.configProvider,
                onSaveConfig: () {
                  widget.formController.updateAllFieldsToProvider(
                    widget.configProvider,
                  );
                  widget.configProvider.saveConfig();
                },
              );
            },
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
