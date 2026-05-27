import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/odbc_drivers.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/database_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/odbc_connection_pool_section.dart';
import 'package:plug_agente/presentation/pages/database_settings/database_connection_form_controller.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/extensions/failure_localization_extensions.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class DatabaseSettingsPage extends StatefulWidget {
  const DatabaseSettingsPage({
    this.configId,
    this.initialTab,
    super.key,
  });

  final String? configId;
  final String? initialTab;

  @override
  State<DatabaseSettingsPage> createState() => _DatabaseSettingsPageState();
}

class _DatabaseSettingsPageState extends State<DatabaseSettingsPage> {
  late int _selectedTabIndex;
  late final DatabaseConnectionFormController _formController;
  final ValueNotifier<bool> _isTesting = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSaving = ValueNotifier<bool>(false);
  ConfigProvider? _configProviderListener;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTab == AppRouteTabs.advanced ? 1 : 0;
    _formController = DatabaseConnectionFormController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _configProviderListener = context.read<ConfigProvider>()..addListener(_onConfigChanged);
      if (widget.configId != null) {
        unawaited(_loadConfig(widget.configId!));
      }
      _checkAndInitializeFields();
    });
  }

  void _onConfigChanged() {
    if (!mounted) {
      return;
    }
    _checkAndInitializeFields();
  }

  @override
  void didUpdateWidget(covariant DatabaseSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configId != widget.configId && widget.configId != null) {
      _formController.resetForConfig();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_loadConfig(widget.configId!));
        _checkAndInitializeFields();
      });
    }
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  void _checkAndInitializeFields() {
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
    if (!_formController.fieldsInitialized && !configProvider.isLoading && configProvider.currentConfig != null) {
      _formController.initializeFromConfig(configProvider.currentConfig);
      // The form controller is not a Listenable; force a rebuild so that
      // `isInitialLoading` flips to false even when the provider state did
      // not change between the load and the initialization.
      setState(() {});
    }
  }

  String? _getValidatedOdbcDriverName(AppLocalizations l10n) {
    final odbcDriverName = _formController.odbcDriverNameController.text.trim();
    if (odbcDriverName.isNotEmpty) {
      return odbcDriverName;
    }

    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleError,
      message: l10n.msgOdbcDriverNameRequired,
    );
    return null;
  }

  Future<bool> _ensureOdbcDriverInstalled({
    required AppLocalizations l10n,
    required ConnectionProvider connectionProvider,
    required String odbcDriverName,
    required String Function(String) notFoundMessageBuilder,
  }) async {
    final driverCheckResult = await connectionProvider.checkOdbcDriver(
      odbcDriverName,
    );

    return driverCheckResult.fold(
      (isInstalled) async {
        if (isInstalled) {
          return true;
        }

        await SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleDriverNotFound,
          message: notFoundMessageBuilder(odbcDriverName),
        );
        return false;
      },
      (failure) async {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleErrorVerifyingDriver,
          message: failure.toDisplayMessage(),
        );
        return false;
      },
    );
  }

  void _showDatabaseConnectionResult(AppLocalizations l10n, bool isConnected) {
    if (isConnected) {
      SettingsFeedback.showSuccess(
        context: context,
        title: l10n.modalTitleConnectionSuccessful,
        message: l10n.msgDatabaseConnectionSuccessful,
      );
      return;
    }

    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleConnectionFailed,
      message: l10n.msgConnectionCheckFailed,
    );
  }

  void _clearProviderError() {
    final provider = _configProviderListener ?? context.read<ConfigProvider>();
    if (provider.error.isNotEmpty) {
      provider.clearError();
    }
  }

  Future<void> _runTestConnection({
    required AppLocalizations l10n,
    required ConfigProvider configProvider,
    required ConnectionProvider connectionProvider,
  }) async {
    _clearProviderError();
    final odbcDriverName = _getValidatedOdbcDriverName(l10n);
    if (odbcDriverName == null) {
      return;
    }

    final isInstalled = await _ensureOdbcDriverInstalled(
      l10n: l10n,
      connectionProvider: connectionProvider,
      odbcDriverName: odbcDriverName,
      notFoundMessageBuilder: l10n.odbcDriverNotFoundTest,
    );
    if (!isInstalled || !mounted) {
      return;
    }

    _isTesting.value = true;
    try {
      _formController.applyToProvider(configProvider);
      final connectionString = configProvider.getConnectionString();
      final testResult = await connectionProvider.testDbConnection(
        connectionString,
      );

      if (!mounted) {
        return;
      }

      testResult.fold(
        (connected) => _showDatabaseConnectionResult(l10n, connected),
        (failure) {
          SettingsFeedback.showError(
            context: context,
            title: l10n.modalTitleErrorTestingConnection,
            message: failure.toDisplayMessageWithOdbcDetailLocalized(
              context,
            ),
          );
        },
      );
    } catch (error, stackTrace) {
      AppLogger.error('Database test connection failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isTesting.value = false;
      }
    }
  }

  Future<void> _runSaveConfig({
    required AppLocalizations l10n,
    required ConfigProvider configProvider,
    required ConnectionProvider connectionProvider,
  }) async {
    _clearProviderError();
    final odbcDriverName = _getValidatedOdbcDriverName(l10n);
    if (odbcDriverName == null) {
      return;
    }

    final isInstalled = await _ensureOdbcDriverInstalled(
      l10n: l10n,
      connectionProvider: connectionProvider,
      odbcDriverName: odbcDriverName,
      notFoundMessageBuilder: l10n.odbcDriverNotFoundSave,
    );
    if (!isInstalled || !mounted) {
      return;
    }

    _isSaving.value = true;
    try {
      _formController.applyToProvider(configProvider);
      final saveResult = await configProvider.saveConfig();

      if (!mounted) {
        return;
      }

      saveResult.fold(
        (_) {
          SettingsFeedback.showSuccess(
            context: context,
            title: l10n.modalTitleConfigSaved,
            message: l10n.msgConfigSavedSuccessfully,
          );
        },
        (failure) {
          SettingsFeedback.showError(
            context: context,
            title: l10n.modalTitleErrorSaving,
            message: failure.toDisplayMessage(),
          );
        },
      );
    } catch (error, stackTrace) {
      AppLogger.error('Database config save failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isSaving.value = false;
      }
    }
  }

  void _onDriverChanged(ConfigProvider configProvider, String value) {
    setState(() {
      configProvider.updateDriverName(value);
      final currentOdbcName = _formController.odbcDriverNameController.text;

      if (OdbcDrivers.isDefaultSuggestion(currentOdbcName)) {
        final suggestion = OdbcDrivers.getDefaultDriver(value);
        if (suggestion.isNotEmpty) {
          _formController.odbcDriverNameController.text = suggestion;
          configProvider.updateOdbcDriverName(suggestion);
        }
      }
    });
  }

  @override
  void dispose() {
    _configProviderListener?.removeListener(_onConfigChanged);
    _isTesting.dispose();
    _isSaving.dispose();
    _formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewModel = context.select<ConfigProvider, _DatabaseSettingsVm>(
      (provider) => _DatabaseSettingsVm(
        isLoading: provider.isLoading,
        error: provider.error,
      ),
    );
    final connectionProvider = context.read<ConnectionProvider>();
    final configProvider = context.read<ConfigProvider>();
    final isInitialLoading = viewModel.isLoading && !_formController.fieldsInitialized;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navDatabaseSettings,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: isInitialLoading
              ? const Center(child: ProgressRing())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (viewModel.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: InfoBar(
                          title: Text(l10n.modalTitleError),
                          content: SelectableText(viewModel.error),
                          severity: InfoBarSeverity.error,
                          isLong: true,
                        ),
                      ),
                    Expanded(
                      child: AppFluentTabView(
                        currentIndex: _selectedTabIndex,
                        onChanged: (index) {
                          setState(() {
                            _selectedTabIndex = index;
                          });
                        },
                        items: [
                          AppFluentTabItem(
                            icon: FluentIcons.database,
                            text: l10n.dbTabDatabase,
                            body: DatabaseConfigSection(
                              formController: _formController,
                              connectionProvider: connectionProvider,
                              isTesting: _isTesting,
                              isSaving: _isSaving,
                              onDriverChanged: (value) => _onDriverChanged(configProvider, value),
                              onTestConnection: () => _runTestConnection(
                                l10n: l10n,
                                configProvider: configProvider,
                                connectionProvider: connectionProvider,
                              ),
                              onSaveConfig: () => _runSaveConfig(
                                l10n: l10n,
                                configProvider: configProvider,
                                connectionProvider: connectionProvider,
                              ),
                            ),
                          ),
                          AppFluentTabItem(
                            icon: FluentIcons.developer_tools,
                            text: l10n.dbTabAdvanced,
                            body: const OdbcConnectionPoolSection(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

@immutable
class _DatabaseSettingsVm {
  const _DatabaseSettingsVm({
    required this.isLoading,
    required this.error,
  });

  final bool isLoading;
  final String error;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _DatabaseSettingsVm && other.isLoading == isLoading && other.error == error;
  }

  @override
  int get hashCode => Object.hash(isLoading, error);
}
