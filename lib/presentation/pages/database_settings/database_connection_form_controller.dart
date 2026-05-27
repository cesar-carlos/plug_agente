import 'package:flutter/material.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

/// Holds the [TextEditingController]s for the database connection form.
///
/// Focused on the inputs the database settings page actually owns, keeping
/// agent profile and websocket fields out of this surface.
class DatabaseConnectionFormController {
  final hostController = TextEditingController();
  final portController = TextEditingController();
  final databaseNameController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final driverNameController = TextEditingController();
  final odbcDriverNameController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

  void resetForConfig() {
    _fieldsInitialized = false;
    hostController.clear();
    portController.clear();
    databaseNameController.clear();
    usernameController.clear();
    passwordController.clear();
    driverNameController.clear();
    odbcDriverNameController.clear();
  }

  void initializeFromConfig(Config? config) {
    if (_fieldsInitialized || config == null) {
      return;
    }

    _setIfEmpty(hostController, config.host);
    _setIfEmpty(portController, config.port.toString());
    _setIfEmpty(databaseNameController, config.databaseName);
    _setIfEmpty(usernameController, config.username);
    _setIfEmpty(passwordController, config.password ?? '');
    _setIfEmpty(driverNameController, config.driverName);
    _setIfEmpty(odbcDriverNameController, config.odbcDriverName);

    _fieldsInitialized = true;
  }

  /// Mirrors the current form values back into the provider, grouped into a
  /// single batch so listeners only fire once per call.
  void applyToProvider(ConfigProvider configProvider) {
    configProvider.batchUpdate(() {
      configProvider.updateHost(hostController.text);
      configProvider.updatePort(int.tryParse(portController.text) ?? 1433);
      configProvider.updateDatabaseName(databaseNameController.text);
      configProvider.updateUsername(usernameController.text);
      configProvider.updatePassword(passwordController.text);
      configProvider.updateDriverName(driverNameController.text);
      configProvider.updateOdbcDriverName(odbcDriverNameController.text);
    });
  }

  void dispose() {
    hostController.dispose();
    portController.dispose();
    databaseNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    driverNameController.dispose();
    odbcDriverNameController.dispose();
  }

  void _setIfEmpty(TextEditingController controller, String value) {
    if (controller.text.isEmpty) {
      controller.text = value;
    }
  }
}
