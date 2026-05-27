import 'package:flutter/material.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

/// Holds the [TextEditingController]s for the WebSocket connection form.
///
/// Focused on the fields the WebSocket settings page actually owns (server
/// URL, agent identifier and optional auth credentials), separated from the
/// agent profile and database forms which have their own controllers.
class WebsocketConfigFormController {
  final serverUrlController = TextEditingController();
  final agentIdController = TextEditingController();
  final authUsernameController = TextEditingController();
  final authPasswordController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

  void resetForConfig() {
    _fieldsInitialized = false;
    serverUrlController.clear();
    agentIdController.clear();
    authUsernameController.clear();
    authPasswordController.clear();
  }

  void initializeFromConfig(Config? config) {
    if (_fieldsInitialized || config == null) {
      return;
    }

    _setIfEmpty(serverUrlController, config.serverUrl);
    _setIfEmpty(agentIdController, config.agentId);
    _setIfEmpty(authUsernameController, config.authUsername ?? '');
    _setIfEmpty(authPasswordController, config.authPassword ?? '');

    _fieldsInitialized = true;
  }

  /// Mirrors the current form values back into the provider, grouped into a
  /// single batch so listeners only fire once per call.
  void applyToProvider(ConfigProvider configProvider) {
    configProvider.batchUpdate(() {
      configProvider.updateServerUrl(serverUrlController.text);
      configProvider.updateAgentId(agentIdController.text);
      configProvider.updateAuthUsername(_trimToNullIfEmpty(authUsernameController.text));
      configProvider.updateAuthPassword(_trimToNullIfEmpty(authPasswordController.text));
    });
  }

  void dispose() {
    serverUrlController.dispose();
    agentIdController.dispose();
    authUsernameController.dispose();
    authPasswordController.dispose();
  }

  void _setIfEmpty(TextEditingController controller, String value) {
    if (controller.text.isEmpty) {
      controller.text = value;
    }
  }

  String? _trimToNullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
