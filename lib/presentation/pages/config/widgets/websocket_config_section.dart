import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_action_buttons.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_client_token_policy_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_config_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_outbound_compression_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_payload_signing_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_server_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_status_section.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/websocket_config_form_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class WebSocketConfigSection extends StatefulWidget {
  const WebSocketConfigSection({
    required this.formController,
    required this.onSaveConfig,
    required this.isSavingConfig,
    super.key,
  });

  final WebsocketConfigFormController formController;
  final Future<void> Function() onSaveConfig;
  final ValueListenable<bool> isSavingConfig;

  @override
  State<WebSocketConfigSection> createState() => _WebSocketConfigSectionState();
}

class _WebSocketConfigSectionState extends State<WebSocketConfigSection> {
  WebSocketConfigController? _controller;

  WebSocketConfigController _ensureController() {
    return _controller ??= WebSocketConfigController(
      configProvider: context.read<ConfigProvider>(),
      authProvider: context.read<AuthProvider>(),
      connectionProvider: context.read<ConnectionProvider>(),
      formController: widget.formController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _ensureController();
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebSocketServerSection(
                formController: widget.formController,
                controller: controller,
              ),
              const SizedBox(height: AppSpacing.lg),
              const WebSocketOutboundCompressionSection(),
              const SizedBox(height: AppSpacing.lg),
              const WebSocketPayloadSigningSection(),
              const SizedBox(height: AppSpacing.lg),
              const WebSocketClientTokenPolicySection(),
              const SizedBox(height: AppSpacing.lg),
              WebSocketActionButtons(
                controller: controller,
                onSaveConfig: widget.onSaveConfig,
                isSavingConfig: widget.isSavingConfig,
              ),
              const SizedBox(height: AppSpacing.md),
              const WebSocketStatusSection(),
            ],
          ),
        ),
      ),
    );
  }
}
