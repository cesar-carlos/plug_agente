import 'package:flutter/material.dart';

import '../../../domain/entities/config.dart';
import '../../providers/config_provider.dart';

class ConfigFormController {
  final TextEditingController serverUrlController = TextEditingController();
  final TextEditingController agentIdController = TextEditingController();
  final TextEditingController authUsernameController = TextEditingController();
  final TextEditingController authPasswordController = TextEditingController();
  final TextEditingController driverNameController = TextEditingController();
  final TextEditingController odbcDriverNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController databaseNameController = TextEditingController();
  final TextEditingController hostController = TextEditingController();
  final TextEditingController portController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

  void initializeFromConfig(Config? config) {
    if (_fieldsInitialized || config == null) return;

    if (serverUrlController.text.isEmpty) {
      serverUrlController.text = config.serverUrl;
    }
    if (agentIdController.text.isEmpty) {
      agentIdController.text = config.agentId;
    }
    if (authUsernameController.text.isEmpty) {
      authUsernameController.text = config.authUsername ?? '';
    }
    if (authPasswordController.text.isEmpty) {
      authPasswordController.text = config.authPassword ?? '';
    }
    if (driverNameController.text.isEmpty) {
      driverNameController.text = config.driverName;
    }
    if (odbcDriverNameController.text.isEmpty) {
      odbcDriverNameController.text = config.odbcDriverName;
    }
    if (usernameController.text.isEmpty) {
      usernameController.text = config.username;
    }
    if (passwordController.text.isEmpty) {
      passwordController.text = config.password ?? '';
    }
    if (databaseNameController.text.isEmpty) {
      databaseNameController.text = config.databaseName;
    }
    if (hostController.text.isEmpty) {
      hostController.text = config.host;
    }
    if (portController.text.isEmpty) {
      portController.text = config.port.toString();
    }

    _fieldsInitialized = true;
  }

  void updateAllFieldsToProvider(ConfigProvider configProvider) {
    configProvider.updateHost(hostController.text);
    configProvider.updatePort(int.tryParse(portController.text) ?? 1433);
    configProvider.updateDatabaseName(databaseNameController.text);
    configProvider.updateUsername(usernameController.text);
    configProvider.updatePassword(passwordController.text);
    configProvider.updateDriverName(driverNameController.text);
    configProvider.updateOdbcDriverName(odbcDriverNameController.text);
    configProvider.updateServerUrl(serverUrlController.text);
    configProvider.updateAgentId(agentIdController.text);
    configProvider.updateAuthUsername(
      authUsernameController.text.trim().isEmpty ? null : authUsernameController.text.trim(),
    );
    configProvider.updateAuthPassword(
      authPasswordController.text.trim().isEmpty ? null : authPasswordController.text.trim(),
    );
  }

  void dispose() {
    serverUrlController.dispose();
    agentIdController.dispose();
    authUsernameController.dispose();
    authPasswordController.dispose();
    driverNameController.dispose();
    odbcDriverNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    databaseNameController.dispose();
    hostController.dispose();
    portController.dispose();
  }
}
