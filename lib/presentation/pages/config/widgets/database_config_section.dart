import 'package:fluent_ui/fluent_ui.dart';

import '../../../../core/constants/odbc_drivers.dart';
import '../../../../domain/value_objects/database_driver.dart';
import '../../../../shared/widgets/common/app_button.dart';
import '../../../../shared/widgets/common/app_card.dart';
import '../../../../shared/widgets/common/app_dropdown.dart';
import '../../../../shared/widgets/common/app_text_field.dart';
import '../../../../shared/widgets/common/numeric_field.dart';
import '../../../../shared/widgets/common/password_field.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/connection_provider.dart';
import '../../../widgets/connection_status_widget.dart';
import '../config_form_controller.dart';

class DatabaseConfigSection extends StatelessWidget {
  const DatabaseConfigSection({
    super.key,
    required this.formController,
    required this.configProvider,
    required this.connectionProvider,
    required this.onDriverChanged,
    required this.onTestConnection,
    required this.onSaveConfig,
  });

  final ConfigFormController formController;
  final ConfigProvider configProvider;
  final ConnectionProvider connectionProvider;
  final ValueChanged<String> onDriverChanged;
  final Future<void> Function() onTestConnection;
  final Future<void> Function() onSaveConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DatabaseSectionHeader(),
            const SizedBox(height: 16),
            _DriverSection(
              driverNameController: formController.driverNameController,
              odbcDriverNameController: formController.odbcDriverNameController,
              onDriverChanged: onDriverChanged,
              fieldsInitialized: formController.fieldsInitialized,
            ),
            const SizedBox(height: 16),
            _ConnectionSection(
              hostController: formController.hostController,
              portController: formController.portController,
            ),
            const SizedBox(height: 16),
            _DatabaseCredentialsSection(
              databaseNameController: formController.databaseNameController,
              usernameController: formController.usernameController,
              passwordController: formController.passwordController,
            ),
            const SizedBox(height: 24),
            _ActionButtons(
              driverNameController: formController.driverNameController,
              odbcDriverNameController: formController.odbcDriverNameController,
              hostController: formController.hostController,
              portController: formController.portController,
              onTestConnection: onTestConnection,
              onSaveConfig: onSaveConfig,
              isLoading: configProvider.isLoading,
              isCheckingDriver: connectionProvider.isCheckingDriver,
            ),
            const SizedBox(height: 16),
            const _StatusSection(),
          ],
        ),
      ),
    );
  }
}

class _DatabaseSectionHeader extends StatelessWidget {
  const _DatabaseSectionHeader();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Configuração do Banco de Dados',
      style: FluentTheme.of(context).typography.subtitle,
    );
  }
}

class _DriverSection extends StatelessWidget {
  const _DriverSection({
    required this.driverNameController,
    required this.odbcDriverNameController,
    required this.onDriverChanged,
    required this.fieldsInitialized,
  });

  final TextEditingController driverNameController;
  final TextEditingController odbcDriverNameController;
  final ValueChanged<String> onDriverChanged;
  final bool fieldsInitialized;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdown<String>(
            label: 'Driver do Banco de Dados',
            value: driverNameController.text,
            items: [
              ComboBoxItem(
                value: DatabaseDriver.sqlServer.displayName,
                child: Text(DatabaseDriver.sqlServer.displayName),
              ),
              ComboBoxItem(
                value: DatabaseDriver.postgreSQL.displayName,
                child: Text(DatabaseDriver.postgreSQL.displayName),
              ),
              ComboBoxItem(
                value: DatabaseDriver.sqlAnywhere.displayName,
                child: Text(DatabaseDriver.sqlAnywhere.displayName),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                driverNameController.text = value;
                onDriverChanged(value);
              }
            },
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Nome do Driver ODBC',
            controller: odbcDriverNameController,
            hint: OdbcDrivers.sqlServerNativeClient,
            enabled: true,
          ),
        ],
      ),
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({
    required this.hostController,
    required this.portController,
  });

  final TextEditingController hostController;
  final TextEditingController portController;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: 'Host',
            controller: hostController,
            hint: 'localhost',
            enabled: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: NumericField(
            label: 'Porta',
            controller: portController,
            hint: '1433',
            minValue: 1,
            maxValue: 65535,
            enabled: true,
          ),
        ),
      ],
    );
  }
}

class _DatabaseCredentialsSection extends StatelessWidget {
  const _DatabaseCredentialsSection({
    required this.databaseNameController,
    required this.usernameController,
    required this.passwordController,
  });

  final TextEditingController databaseNameController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Nome do Banco de Dados',
          controller: databaseNameController,
          hint: 'Nome da Base',
          enabled: true,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Usuário',
          controller: usernameController,
          hint: 'Usuário',
          enabled: true,
        ),
        const SizedBox(height: 16),
        PasswordField(
          label: 'Senha',
          controller: passwordController,
          hint: 'Senha',
          validator: null,
          enabled: true,
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.driverNameController,
    required this.odbcDriverNameController,
    required this.hostController,
    required this.portController,
    required this.onTestConnection,
    required this.onSaveConfig,
    required this.isLoading,
    required this.isCheckingDriver,
  });

  final TextEditingController driverNameController;
  final TextEditingController odbcDriverNameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final Future<void> Function() onTestConnection;
  final Future<void> Function() onSaveConfig;
  final bool isLoading;
  final bool isCheckingDriver;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppButton(
          label: 'Testar Conexão com Banco',
          isPrimary: false,
          isLoading: isCheckingDriver,
          onPressed: () {
            if (driverNameController.text.isNotEmpty &&
                hostController.text.isNotEmpty &&
                portController.text.isNotEmpty &&
                odbcDriverNameController.text.isNotEmpty) {
              onTestConnection();
            }
          },
        ),
        const SizedBox(width: 16),
        AppButton(
          label: 'Salvar Configuração',
          isLoading: isLoading || isCheckingDriver,
          onPressed: () {
            if (driverNameController.text.isNotEmpty &&
                hostController.text.isNotEmpty &&
                portController.text.isNotEmpty &&
                odbcDriverNameController.text.isNotEmpty) {
              onSaveConfig();
            }
          },
        ),
      ],
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return const ConnectionStatusWidget();
  }
}
