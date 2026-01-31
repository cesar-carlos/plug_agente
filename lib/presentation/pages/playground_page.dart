import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/shared/shared.dart';
import 'package:provider/provider.dart';

class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({
    this.configId,
    super.key,
  });

  final String? configId;

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _focusNode = FocusNode();

    if (widget.configId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadConfig(widget.configId!);
      });
    }
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showErrorModal(String error) {
    if (!mounted) return;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show<void>(
      context: navigatorContext,
      title: 'Erro',
      message: error,
      type: MessageType.error,
    );
  }

  void _showConnectionStatusModal(String status, bool isSuccess) {
    if (!mounted) return;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show<void>(
      context: navigatorContext,
      title: 'Status da Conexão',
      message: status,
      type: isSuccess ? MessageType.success : MessageType.error,
    );
  }

  Future<void> _handleExecute(PlaygroundProvider provider) async {
    provider.setQuery(_queryController.text);
    await provider.executeQuery();
    if (!mounted) return;

    final error = provider.error;
    if (error != null) {
      _showErrorModal(error);
    }
  }

  Future<void> _handleTestConnection(
    ConfigProvider configProvider,
    PlaygroundProvider provider,
  ) async {
    final config = configProvider.currentConfig;
    if (config == null) return;

    await provider.testConnection(config);
    if (!mounted) return;

    final connectionStatus = provider.connectionStatus;
    final error = provider.error;
    if (connectionStatus != null) {
      final isSuccess = connectionStatus.contains('sucesso');
      _showConnectionStatusModal(connectionStatus, isSuccess);
    } else if (error != null) {
      _showErrorModal(error);
    }
  }

  void _handleClear(PlaygroundProvider provider) {
    _queryController.clear();
    provider.clearResults();
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    PlaygroundProvider playgroundProvider,
    ConfigProvider configProvider,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    // F5 or Ctrl+Enter: Execute query
    if (event.logicalKey == LogicalKeyboardKey.f5 ||
        (isControlPressed && event.logicalKey == LogicalKeyboardKey.enter)) {
      _handleExecute(playgroundProvider);
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+C: Test connection
    if (isControlPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _handleTestConnection(configProvider, playgroundProvider);
      return KeyEventResult.handled;
    }

    // Ctrl+L: Clear
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
      _handleClear(playgroundProvider);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Playground Database')),
      content: Consumer2<PlaygroundProvider, ConfigProvider>(
        builder: (context, playgroundProvider, configProvider, _) {
          final config = configProvider.currentConfig;

          return Focus(
            focusNode: _focusNode,
            onKeyEvent: (node, event) => _handleKeyEvent(
              event,
              playgroundProvider,
              configProvider,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SqlEditor(
                    controller: _queryController,
                    onChanged: (value) {
                      playgroundProvider.setQuery(value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SqlActionBar(
                    onExecute: () => _handleExecute(playgroundProvider),
                    onTestConnection: config != null
                        ? () => _handleTestConnection(
                            configProvider,
                            playgroundProvider,
                          )
                        : null,
                    onClear: () => _handleClear(playgroundProvider),
                    onCancel: () => playgroundProvider.cancelQuery(),
                    isExecuting: playgroundProvider.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: QueryResultsSection(
                      results: playgroundProvider.results,
                      isLoading: playgroundProvider.isLoading,
                      executionDuration: playgroundProvider.executionDuration,
                      affectedRows: playgroundProvider.affectedRows,
                      columnMetadata: playgroundProvider.columnMetadata,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
