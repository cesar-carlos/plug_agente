import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/odbc_drivers.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/database_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/odbc_connection_pool_section.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
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
  late int _currentPage;
  late final ConfigFormController _formController;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialTab == 'advanced' ? 1 : 0;
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
    if (!_formController.fieldsInitialized &&
        !configProvider.isLoading &&
        configProvider.currentConfig != null) {
      _formController.initializeFromConfig(configProvider.currentConfig);
    } else if (configProvider.isLoading) {
      Future.delayed(
        const Duration(milliseconds: 100),
        _checkAndInitializeFields,
      );
    }
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
          'Banco de dados',
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          maxWidth: AppLayout.maxSettingsWidth,
          child: Column(
            children: [
              _DatabaseSettingsTabs(
                currentPage: _currentPage,
                onDatabaseTabTap: () => setState(() => _currentPage = 0),
                onAdvancedTabTap: () => setState(() => _currentPage = 1),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: _currentPage == 0
                    ? DatabaseConfigSection(
                        formController: _formController,
                        configProvider: configProvider,
                        connectionProvider: connectionProvider,
                        onDriverChanged: (value) {
                          setState(() {
                            configProvider.updateDriverName(value);
                            final currentOdbcName =
                                _formController.odbcDriverNameController.text;

                            if (OdbcDrivers.isDefaultSuggestion(
                              currentOdbcName,
                            )) {
                              final suggestion = OdbcDrivers.getDefaultDriver(
                                value,
                              );
                              if (suggestion.isNotEmpty) {
                                _formController.odbcDriverNameController.text =
                                    suggestion;
                                configProvider.updateOdbcDriverName(suggestion);
                              }
                            }
                          });
                        },
                        onTestConnection: () async {
                          final odbcDriverName = _formController
                              .odbcDriverNameController
                              .text
                              .trim();
                          if (odbcDriverName.isEmpty) {
                            MessageModal.show<void>(
                              context: context,
                              title: 'Erro',
                              message: 'Nome do Driver ODBC é obrigatório',
                              type: MessageType.error,
                              confirmText: 'OK',
                            );
                            return;
                          }

                          final driverCheckResult = await connectionProvider
                              .checkOdbcDriver(odbcDriverName);
                          await driverCheckResult.fold(
                            (isInstalled) async {
                              if (!isInstalled) {
                                MessageModal.show<void>(
                                  context: context,
                                  title: 'Driver Não Encontrado',
                                  message:
                                      'Driver ODBC "$odbcDriverName" não foi encontrado. Verifique se o driver está instalado antes de testar a conexão.',
                                  type: MessageType.error,
                                  confirmText: 'OK',
                                );
                                return;
                              }

                              _formController.updateAllFieldsToProvider(
                                configProvider,
                              );
                              final connectionString = configProvider
                                  .getConnectionString();
                              final testResult = await connectionProvider
                                  .testDbConnection(connectionString);

                              if (!mounted) {
                                return;
                              }

                              testResult.fold(
                                (isConnected) {
                                  MessageModal.show<void>(
                                    context: context,
                                    title: isConnected
                                        ? 'Conexão Bem-Sucedida'
                                        : 'Falha na Conexão',
                                    message: isConnected
                                        ? 'Conexão com o banco de dados estabelecida com sucesso!'
                                        : 'Não foi possível conectar ao banco de dados. Verifique as credenciais e configurações.',
                                    type: isConnected
                                        ? MessageType.success
                                        : MessageType.error,
                                    confirmText: 'OK',
                                  );
                                },
                                (failure) {
                                  final failureMessage =
                                      failure is domain.Failure
                                      ? failure.message
                                      : failure.toString();
                                  MessageModal.show<void>(
                                    context: context,
                                    title: 'Erro ao Testar Conexão',
                                    message: failureMessage,
                                    type: MessageType.error,
                                    confirmText: 'OK',
                                  );
                                },
                              );
                            },
                            (failure) async {
                              final failureMessage = failure is domain.Failure
                                  ? failure.message
                                  : failure.toString();
                              MessageModal.show<void>(
                                context: context,
                                title: 'Erro ao Verificar Driver',
                                message: failureMessage,
                                type: MessageType.error,
                                confirmText: 'OK',
                              );
                            },
                          );
                        },
                        onSaveConfig: () async {
                          final odbcDriverName = _formController
                              .odbcDriverNameController
                              .text
                              .trim();
                          if (odbcDriverName.isEmpty) {
                            MessageModal.show<void>(
                              context: context,
                              title: 'Erro',
                              message: 'Nome do Driver ODBC é obrigatório',
                              type: MessageType.error,
                              confirmText: 'OK',
                            );
                            return;
                          }

                          final driverCheckResult = await connectionProvider
                              .checkOdbcDriver(odbcDriverName);
                          await driverCheckResult.fold(
                            (isInstalled) async {
                              if (!isInstalled) {
                                MessageModal.show<void>(
                                  context: context,
                                  title: 'Driver Não Encontrado',
                                  message:
                                      'Driver ODBC "$odbcDriverName" não foi encontrado. Verifique se o driver está instalado antes de salvar a configuração.',
                                  type: MessageType.error,
                                  confirmText: 'OK',
                                );
                                return;
                              }

                              _formController.updateAllFieldsToProvider(
                                configProvider,
                              );
                              final saveResult = await configProvider
                                  .saveConfig();

                              if (!mounted) {
                                return;
                              }

                              saveResult.fold(
                                (_) {
                                  MessageModal.show<void>(
                                    context: context,
                                    title: 'Configuração Salva',
                                    message: 'Configuração salva com sucesso!',
                                    type: MessageType.success,
                                    confirmText: 'OK',
                                  );
                                },
                                (failure) {
                                  final failureMessage =
                                      failure is domain.Failure
                                      ? failure.message
                                      : failure.toString();
                                  MessageModal.show<void>(
                                    context: context,
                                    title: 'Erro ao Salvar',
                                    message: failureMessage,
                                    type: MessageType.error,
                                    confirmText: 'OK',
                                  );
                                },
                              );
                            },
                            (failure) async {
                              final failureMessage = failure is domain.Failure
                                  ? failure.message
                                  : failure.toString();
                              MessageModal.show<void>(
                                context: context,
                                title: 'Erro ao Verificar Driver',
                                message: failureMessage,
                                type: MessageType.error,
                                confirmText: 'OK',
                              );
                            },
                          );
                        },
                      )
                    : const OdbcConnectionPoolSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseSettingsTabs extends StatelessWidget {
  const _DatabaseSettingsTabs({
    required this.currentPage,
    required this.onDatabaseTabTap,
    required this.onAdvancedTabTap,
  });

  final int currentPage;
  final VoidCallback onDatabaseTabTap;
  final VoidCallback onAdvancedTabTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          _TabButton(
            label: 'Banco de dados',
            icon: FluentIcons.database,
            isSelected: currentPage == 0,
            onTap: onDatabaseTabTap,
          ),
          _TabSeparator(color: theme.resources.controlStrokeColorDefault),
          _TabButton(
            label: 'Avançado',
            icon: FluentIcons.developer_tools,
            isSelected: currentPage == 1,
            onTap: onAdvancedTabTap,
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final backgroundColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.2)
        : Colors.transparent;
    final textColor = isSelected
        ? AppColors.primary
        : theme.resources.textFillColorPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.bodyText.copyWith(
                    color: textColor,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabSeparator extends StatelessWidget {
  const _TabSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: AppSpacing.md + 2,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
      color: color.withValues(alpha: 0.4),
    );
  }
}
