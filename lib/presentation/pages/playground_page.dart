import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/shared/shared.dart';
import 'package:provider/provider.dart';

const _playgroundStreamingModeKey = 'playground_streaming_mode_enabled';
const _playgroundSqlHandlingModeKey = 'playground_sql_handling_mode';

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
  bool _streamingModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _focusNode = FocusNode();
    unawaited(
      _restoreStreamingMode().catchError(
        (Object e) => AppLogger.warning('Failed to restore streaming mode', e),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _restoreSqlHandlingMode().catchError(
          (Object e) =>
              AppLogger.warning('Failed to restore SQL handling mode', e),
        ),
      );
    });

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

  Future<void> _restoreStreamingMode() async {
    final prefs = getIt<IAppSettingsStore>();
    final enabled = prefs.getBool(_playgroundStreamingModeKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() => _streamingModeEnabled = enabled);
  }

  Future<void> _saveStreamingMode(bool enabled) async {
    final prefs = getIt<IAppSettingsStore>();
    await prefs.setBool(_playgroundStreamingModeKey, enabled);
  }

  Future<void> _restoreSqlHandlingMode() async {
    final prefs = getIt<IAppSettingsStore>();
    final preserve = prefs.getBool(_playgroundSqlHandlingModeKey) ?? false;
    if (!mounted) return;
    context.read<PlaygroundProvider>().setSqlHandlingMode(
      preserve ? SqlHandlingMode.preserve : SqlHandlingMode.managed,
    );
    if (preserve && mounted) {
      setState(() => _streamingModeEnabled = false);
      unawaited(
        _saveStreamingMode(false).catchError(
          (Object e) => AppLogger.warning(
            'Failed to sync streaming mode with preserve',
            e,
          ),
        ),
      );
    }
  }

  Future<void> _saveSqlHandlingMode(bool preserve) async {
    final prefs = getIt<IAppSettingsStore>();
    await prefs.setBool(_playgroundSqlHandlingModeKey, preserve);
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
      title: AppStrings.queryErrorTitle,
      message: error,
      type: MessageType.error,
    );
  }

  void _showConnectionStatusModal(String status, bool isSuccess) {
    if (!mounted) return;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show<void>(
      context: navigatorContext,
      title: AppStrings.queryConnectionStatusTitle,
      message: status,
      type: isSuccess ? MessageType.success : MessageType.error,
    );
  }

  Future<void> _handleExecute(
    PlaygroundProvider provider,
    ConfigProvider configProvider,
  ) async {
    provider.setQuery(_queryController.text);
    final config = configProvider.currentConfig;

    if (_streamingModeEnabled && config != null) {
      await provider.executeQueryWithStreaming(
        _queryController.text,
        config.connectionString,
      );
    } else {
      await provider.executeQuery(resetPagination: true);
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
    final isConnectionStatusSuccess = provider.isConnectionStatusSuccess;
    final error = provider.error;
    if (connectionStatus != null && isConnectionStatusSuccess != null) {
      _showConnectionStatusModal(
        connectionStatus,
        isConnectionStatusSuccess,
      );
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
      _handleExecute(playgroundProvider, configProvider);
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
      header: PageHeader(
        title: Text(
          AppStrings.titlePlayground,
          style: context.sectionTitle,
        ),
      ),
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
              padding: AppLayout.pagePadding(context),
              child: AppLayout.centeredContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.playgroundDescription,
                            style: context.bodyMuted,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _PlaygroundShortcutChip(
                                icon: FluentIcons.play,
                                label: AppStrings.playgroundShortcutExecute,
                              ),
                              _PlaygroundShortcutChip(
                                icon: FluentIcons.plug_connected,
                                label:
                                    AppStrings.playgroundShortcutTestConnection,
                              ),
                              _PlaygroundShortcutChip(
                                icon: FluentIcons.clear,
                                label: AppStrings.playgroundShortcutClear,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const ConnectionStatusWidget(),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SqlEditor(
                      controller: _queryController,
                      onChanged: (value) {
                        playgroundProvider.setQuery(value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SqlActionBar(
                            onExecute: () => _handleExecute(
                              playgroundProvider,
                              configProvider,
                            ),
                            onTestConnection: config != null
                                ? () => _handleTestConnection(
                                    configProvider,
                                    playgroundProvider,
                                  )
                                : null,
                            onClear: () => _handleClear(playgroundProvider),
                            onCancel: () => playgroundProvider.cancelQuery(),
                            isExecuting: playgroundProvider.isLoading,
                            streamingModeEnabled: _streamingModeEnabled,
                            onStreamingModeChanged: (value) {
                              setState(() => _streamingModeEnabled = value);
                              unawaited(
                                _saveStreamingMode(value).catchError(
                                  (Object e) => AppLogger.warning(
                                    'Failed to save streaming mode',
                                    e,
                                  ),
                                ),
                              );
                            },
                            sqlHandlingModePreserve:
                                playgroundProvider.sqlHandlingMode ==
                                SqlHandlingMode.preserve,
                            onSqlHandlingModeChanged: (value) {
                              playgroundProvider.setSqlHandlingMode(
                                value
                                    ? SqlHandlingMode.preserve
                                    : SqlHandlingMode.managed,
                              );
                              if (value) {
                                setState(() => _streamingModeEnabled = false);
                                unawaited(
                                  _saveStreamingMode(false).catchError(
                                    (Object e) => AppLogger.warning(
                                      'Failed to save streaming mode',
                                      e,
                                    ),
                                  ),
                                );
                              }
                              unawaited(
                                _saveSqlHandlingMode(value).catchError(
                                  (Object e) => AppLogger.warning(
                                    'Failed to save SQL handling mode',
                                    e,
                                  ),
                                ),
                              );
                            },
                            useStreamingMode:
                                config != null &&
                                playgroundProvider.sqlHandlingMode !=
                                    SqlHandlingMode.preserve,
                          ),
                          if (playgroundProvider.lastExecutionHint != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              playgroundProvider.lastExecutionHint!,
                              style: context.bodyMuted,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: QueryResultsSection(
                        results: playgroundProvider.results,
                        isLoading: playgroundProvider.isLoading,
                        isStreaming: playgroundProvider.isStreaming,
                        rowsProcessed: playgroundProvider.rowsProcessed,
                        progress: playgroundProvider.progress,
                        executionDuration: playgroundProvider.executionDuration,
                        affectedRows: playgroundProvider.affectedRows,
                        columnMetadata: playgroundProvider.columnMetadata,
                        error: playgroundProvider.error,
                        currentPage: playgroundProvider.currentPage,
                        pageSize: playgroundProvider.pageSize,
                        hasNextPage: playgroundProvider.hasNextPage,
                        hasPreviousPage: playgroundProvider.hasPreviousPage,
                        showPagination:
                            playgroundProvider.hasPagination &&
                            playgroundProvider.sqlHandlingMode !=
                                SqlHandlingMode.preserve,
                        resultSetCount: playgroundProvider.resultSets.length,
                        selectedResultSetIndex:
                            playgroundProvider.selectedResultSetIndex,
                        onPreviousPage:
                            playgroundProvider.sqlHandlingMode !=
                                    SqlHandlingMode.preserve &&
                                playgroundProvider.hasPreviousPage
                            ? () => playgroundProvider.goToPreviousPage()
                            : null,
                        onNextPage:
                            playgroundProvider.sqlHandlingMode !=
                                    SqlHandlingMode.preserve &&
                                playgroundProvider.hasNextPage
                            ? () => playgroundProvider.goToNextPage()
                            : null,
                        onResultSetChanged:
                            playgroundProvider.hasMultipleResultSets
                            ? playgroundProvider.setSelectedResultSetIndex
                            : null,
                        onPageSizeChanged:
                            playgroundProvider.sqlHandlingMode !=
                                SqlHandlingMode.preserve
                            ? (value) {
                                unawaited(
                                  playgroundProvider
                                      .setPageSize(value)
                                      .catchError(
                                        (Object e) => AppLogger.warning(
                                          'Failed to set page size',
                                          e,
                                        ),
                                      ),
                                );
                              }
                            : null,
                        onShowErrorDetails: playgroundProvider.error != null
                            ? () => _showErrorModal(playgroundProvider.error!)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlaygroundShortcutChip extends StatelessWidget {
  const _PlaygroundShortcutChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: context.bodyMuted),
        ],
      ),
    );
  }
}
