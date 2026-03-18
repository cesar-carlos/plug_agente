import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/constants/odbc_drivers.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/database_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/odbc_connection_pool_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/settings_tab_view.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
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
  late final ConfigFormController _formController;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTab == 'advanced' ? 1 : 0;
    _formController = ConfigFormController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.configId != null) {
        _loadConfig(widget.configId!);
      }
      _checkAndInitializeFields();
    });
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

  String? _getValidatedOdbcDriverName() {
    final odbcDriverName = _formController.odbcDriverNameController.text.trim();
    if (odbcDriverName.isNotEmpty) {
      return odbcDriverName;
    }

    SettingsFeedback.showError(
      context: context,
      title: AppStrings.modalTitleError,
      message: AppStrings.msgOdbcDriverNameRequired,
    );
    return null;
  }

  Future<bool> _ensureOdbcDriverInstalled({
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
          title: AppStrings.modalTitleDriverNotFound,
          message: notFoundMessageBuilder(odbcDriverName),
        );
        return false;
      },
      (failure) async {
        await SettingsFeedback.showError(
          context: context,
          title: AppStrings.modalTitleErrorVerifyingDriver,
          message: failure.toDisplayMessage(),
        );
        return false;
      },
    );
  }

  void _showDatabaseConnectionResult(bool isConnected) {
    if (isConnected) {
      SettingsFeedback.showSuccess(
        context: context,
        title: AppStrings.modalTitleConnectionSuccessful,
        message: AppStrings.msgDatabaseConnectionSuccessful,
      );
      return;
    }

    SettingsFeedback.showError(
      context: context,
      title: AppStrings.modalTitleConnectionFailed,
      message: AppStrings.msgConnectionCheckFailed,
    );
  }

  @override
  void dispose() {
    _formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = context.read<ConfigProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          AppStrings.navDatabaseSettings,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: SettingsTabView(
            currentIndex: _selectedTabIndex,
            onChanged: (index) {
              setState(() {
                _selectedTabIndex = index;
              });
            },
            items: [
              SettingsTabItem(
                icon: FluentIcons.database,
                text: AppStrings.dbTabDatabase,
                body: DatabaseConfigSection(
                  formController: _formController,
                  configProvider: configProvider,
                  connectionProvider: connectionProvider,
                  onDriverChanged: (value) {
                    setState(() {
                      configProvider.updateDriverName(value);
                      final currentOdbcName = _formController.odbcDriverNameController.text;

                      if (OdbcDrivers.isDefaultSuggestion(
                        currentOdbcName,
                      )) {
                        final suggestion = OdbcDrivers.getDefaultDriver(
                          value,
                        );
                        if (suggestion.isNotEmpty) {
                          _formController.odbcDriverNameController.text = suggestion;
                          configProvider.updateOdbcDriverName(suggestion);
                        }
                      }
                    });
                  },
                  onTestConnection: () async {
                    final odbcDriverName = _getValidatedOdbcDriverName();
                    if (odbcDriverName == null) {
                      return;
                    }

                    final isInstalled = await _ensureOdbcDriverInstalled(
                      connectionProvider: connectionProvider,
                      odbcDriverName: odbcDriverName,
                      notFoundMessageBuilder: AppStrings.driverNotFoundForTest,
                    );
                    if (!isInstalled) {
                      return;
                    }

                    _formController.updateAllFieldsToProvider(
                      configProvider,
                    );
                    final connectionString = configProvider.getConnectionString();
                    final testResult = await connectionProvider.testDbConnection(
                      connectionString,
                    );

                    if (!mounted) {
                      return;
                    }

                    testResult.fold(
                      _showDatabaseConnectionResult,
                      (failure) {
                        SettingsFeedback.showError(
                          context: context,
                          title: AppStrings.modalTitleErrorTestingConnection,
                          message: failure.toDisplayMessage(),
                        );
                      },
                    );
                  },
                  onSaveConfig: () async {
                    final odbcDriverName = _getValidatedOdbcDriverName();
                    if (odbcDriverName == null) {
                      return;
                    }

                    final isInstalled = await _ensureOdbcDriverInstalled(
                      connectionProvider: connectionProvider,
                      odbcDriverName: odbcDriverName,
                      notFoundMessageBuilder: AppStrings.driverNotFoundForSave,
                    );
                    if (!isInstalled) {
                      return;
                    }

                    _formController.updateAllFieldsToProvider(
                      configProvider,
                    );
                    final saveResult = await configProvider.saveConfig();

                    if (!mounted) {
                      return;
                    }

                    saveResult.fold(
                      (_) {
                        SettingsFeedback.showSuccess(
                          context: context,
                          title: AppStrings.modalTitleConfigSaved,
                          message: AppStrings.msgConfigSavedSuccessfully,
                        );
                      },
                      (failure) {
                        SettingsFeedback.showError(
                          context: context,
                          title: AppStrings.modalTitleErrorSaving,
                          message: failure.toDisplayMessage(),
                        );
                      },
                    );
                  },
                ),
              ),
              const SettingsTabItem(
                icon: FluentIcons.developer_tools,
                text: AppStrings.dbTabAdvanced,
                body: OdbcConnectionPoolSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
