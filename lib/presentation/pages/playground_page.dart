import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/mappers/playground_ui_strings.dart';
import 'package:plug_agente/presentation/pages/playground/playground_page_settings_controller.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
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
  static const PlaygroundPageSettingsController _settingsController = PlaygroundPageSettingsController();

  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  bool _streamingModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryController.addListener(_onQueryTextChanged);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_restoreStreamingMode());
      unawaited(_restoreSqlHandlingMode());
    });

    if (widget.configId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadConfig(widget.configId!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant PlaygroundPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configId != widget.configId && widget.configId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _loadConfig(widget.configId!);
      });
    }
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  IAppSettingsStore? _settingsStore(BuildContext context) =>
      readOptionalPresentationProvider<IAppSettingsStore>(context);

  Future<void> _restoreStreamingMode() async {
    await _settingsController.restoreStreamingModeSafely(
      _settingsStore(context),
      (enabled) {
        if (!mounted) {
          return;
        }
        setState(() => _streamingModeEnabled = enabled);
      },
    );
  }

  Future<void> _restoreSqlHandlingMode() async {
    await _settingsController.restoreSqlHandlingModeSafely(
      _settingsStore(context),
      (mode) {
        if (!mounted) {
          return;
        }
        context.read<PlaygroundProvider>().setSqlHandlingMode(mode);
        if (mode == SqlHandlingMode.preserve) {
          setState(() => _streamingModeEnabled = false);
          unawaited(_settingsController.saveStreamingModeSafely(_settingsStore(context), false));
        }
      },
    );
  }

  Future<void> _saveStreamingMode(bool enabled) {
    return _settingsController.saveStreamingMode(_settingsStore(context), enabled);
  }

  Future<void> _saveSqlHandlingMode(bool preserve) {
    return _settingsController.saveSqlHandlingMode(_settingsStore(context), preserve);
  }

  void _onQueryTextChanged() {
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    context.read<PlaygroundProvider>().bindUiStrings(PlaygroundUiStrings.fromL10n(l10n));
  }

  bool _canExecutePlaygroundQuery({required bool hasConfig}) => hasConfig && _queryController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _queryController.removeListener(_onQueryTextChanged);
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showErrorModal(String error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show<void>(
      context: navigatorContext,
      title: l10n.queryErrorTitle,
      message: error,
      type: MessageType.error,
    );
  }

  void _showConnectionStatusModal(String status, bool isSuccess) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show<void>(
      context: navigatorContext,
      title: l10n.queryConnectionStatusTitle,
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
      await provider.executeQuery(
        resetPagination: true,
        configId: config?.id ?? widget.configId,
      );
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
  ) {
    final playgroundProvider = context.read<PlaygroundProvider>();
    final configProvider = context.read<ConfigProvider>();
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    // F5 or Ctrl+Enter: Execute query (only when config is available)
    if (event.logicalKey == LogicalKeyboardKey.f5 ||
        (isControlPressed && event.logicalKey == LogicalKeyboardKey.enter)) {
      final hasConfig = configProvider.currentConfig != null || widget.configId != null;
      if (!_canExecutePlaygroundQuery(hasConfig: hasConfig)) {
        return KeyEventResult.handled;
      }
      _handleExecute(playgroundProvider, configProvider);
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+C: Test connection
    if (isControlPressed && isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
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
    final l10n = AppLocalizations.of(context)!;
    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.titlePlayground,
          style: context.sectionTitle,
        ),
      ),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) => _handleKeyEvent(event),
        child: Padding(
          padding: AppLayout.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.playgroundDescription,
                      style: context.bodyMuted,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _PlaygroundShortcutChip(
                          icon: FluentIcons.play,
                          label: l10n.playgroundShortcutExecute,
                        ),
                        _PlaygroundShortcutChip(
                          icon: FluentIcons.plug_connected,
                          label: l10n.playgroundShortcutTestConnection,
                        ),
                        _PlaygroundShortcutChip(
                          icon: FluentIcons.clear,
                          label: l10n.playgroundShortcutClear,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const ConnectionStatusWidget(compact: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SqlEditor(
                controller: _queryController,
                onChanged: context.read<PlaygroundProvider>().setQuery,
              ),
              const SizedBox(height: AppSpacing.md),
              Selector2<ConfigProvider, PlaygroundProvider, (bool, _PlaygroundActionBarState)>(
                selector: (_, configProvider, playgroundProvider) => (
                  configProvider.currentConfig != null,
                  _PlaygroundActionBarState(
                    isLoading: playgroundProvider.isLoading,
                    sqlHandlingMode: playgroundProvider.sqlHandlingMode,
                    lastExecutionHint: playgroundProvider.lastExecutionHint,
                  ),
                ),
                builder: (context, selected, _) {
                  final hasConfig = selected.$1 || widget.configId != null;
                  final actionBarState = selected.$2;
                  final playgroundProvider = context.read<PlaygroundProvider>();
                  final configProvider = context.read<ConfigProvider>();
                  final config = configProvider.currentConfig;

                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SqlActionBar(
                          onExecute: _canExecutePlaygroundQuery(hasConfig: hasConfig)
                              ? () => _handleExecute(playgroundProvider, configProvider)
                              : null,
                          onTestConnection: config != null
                              ? () => _handleTestConnection(configProvider, playgroundProvider)
                              : null,
                          onClear: () => _handleClear(playgroundProvider),
                          onCancel: playgroundProvider.cancelQuery,
                          isExecuting: actionBarState.isLoading,
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
                          sqlHandlingModePreserve: actionBarState.sqlHandlingMode == SqlHandlingMode.preserve,
                          onSqlHandlingModeChanged: (value) {
                            playgroundProvider.setSqlHandlingMode(
                              value ? SqlHandlingMode.preserve : SqlHandlingMode.managed,
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
                              config != null && actionBarState.sqlHandlingMode != SqlHandlingMode.preserve,
                        ),
                        if (actionBarState.lastExecutionHint != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            actionBarState.lastExecutionHint!,
                            style: context.bodyMuted,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Selector<PlaygroundProvider, _PlaygroundResultsState>(
                  selector: (_, provider) => _PlaygroundResultsState(
                    results: provider.results,
                    isLoading: provider.isLoading,
                    isStreaming: provider.isStreaming,
                    rowsProcessed: provider.rowsProcessed,
                    progress: provider.progress,
                    executionDuration: provider.executionDuration,
                    affectedRows: provider.affectedRows,
                    columnMetadata: provider.columnMetadata,
                    error: provider.error,
                    currentPage: provider.currentPage,
                    pageSize: provider.pageSize,
                    hasNextPage: provider.hasNextPage,
                    hasPreviousPage: provider.hasPreviousPage,
                    hasPagination: provider.hasPagination,
                    sqlHandlingMode: provider.sqlHandlingMode,
                    resultSetCount: provider.resultSets.length,
                    selectedResultSetIndex: provider.selectedResultSetIndex,
                    hasMultipleResultSets: provider.hasMultipleResultSets,
                  ),
                  builder: (context, state, _) {
                    final playgroundProvider = context.read<PlaygroundProvider>();
                    return QueryResultsSection(
                      results: state.results,
                      isLoading: state.isLoading,
                      isStreaming: state.isStreaming,
                      rowsProcessed: state.rowsProcessed,
                      progress: state.progress,
                      executionDuration: state.executionDuration,
                      affectedRows: state.affectedRows,
                      columnMetadata: state.columnMetadata,
                      error: state.error,
                      currentPage: state.currentPage,
                      pageSize: state.pageSize,
                      hasNextPage: state.hasNextPage,
                      hasPreviousPage: state.hasPreviousPage,
                      showPagination: state.hasPagination && state.sqlHandlingMode != SqlHandlingMode.preserve,
                      resultSetCount: state.resultSetCount,
                      selectedResultSetIndex: state.selectedResultSetIndex,
                      onPreviousPage: state.sqlHandlingMode != SqlHandlingMode.preserve && state.hasPreviousPage
                          ? playgroundProvider.goToPreviousPage
                          : null,
                      onNextPage: state.sqlHandlingMode != SqlHandlingMode.preserve && state.hasNextPage
                          ? playgroundProvider.goToNextPage
                          : null,
                      onResultSetChanged: state.hasMultipleResultSets
                          ? playgroundProvider.setSelectedResultSetIndex
                          : null,
                      onPageSizeChanged: state.sqlHandlingMode != SqlHandlingMode.preserve
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
                      onShowErrorDetails: state.error != null ? () => _showErrorModal(state.error!) : null,
                    );
                  },
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
class _PlaygroundActionBarState {
  const _PlaygroundActionBarState({
    required this.isLoading,
    required this.sqlHandlingMode,
    required this.lastExecutionHint,
  });

  final bool isLoading;
  final SqlHandlingMode sqlHandlingMode;
  final String? lastExecutionHint;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _PlaygroundActionBarState &&
            isLoading == other.isLoading &&
            sqlHandlingMode == other.sqlHandlingMode &&
            lastExecutionHint == other.lastExecutionHint;
  }

  @override
  int get hashCode => Object.hash(isLoading, sqlHandlingMode, lastExecutionHint);
}

@immutable
class _PlaygroundResultsState {
  const _PlaygroundResultsState({
    required this.results,
    required this.isLoading,
    required this.isStreaming,
    required this.rowsProcessed,
    required this.progress,
    required this.executionDuration,
    required this.affectedRows,
    required this.columnMetadata,
    required this.error,
    required this.currentPage,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.hasPagination,
    required this.sqlHandlingMode,
    required this.resultSetCount,
    required this.selectedResultSetIndex,
    required this.hasMultipleResultSets,
  });

  final List<Map<String, dynamic>> results;
  final bool isLoading;
  final bool isStreaming;
  final int rowsProcessed;
  final double progress;
  final Duration? executionDuration;
  final int? affectedRows;
  final List<Map<String, dynamic>>? columnMetadata;
  final String? error;
  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final bool hasPagination;
  final SqlHandlingMode sqlHandlingMode;
  final int resultSetCount;
  final int selectedResultSetIndex;
  final bool hasMultipleResultSets;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _PlaygroundResultsState &&
            isLoading == other.isLoading &&
            isStreaming == other.isStreaming &&
            rowsProcessed == other.rowsProcessed &&
            progress == other.progress &&
            executionDuration == other.executionDuration &&
            affectedRows == other.affectedRows &&
            error == other.error &&
            currentPage == other.currentPage &&
            pageSize == other.pageSize &&
            hasNextPage == other.hasNextPage &&
            hasPreviousPage == other.hasPreviousPage &&
            hasPagination == other.hasPagination &&
            sqlHandlingMode == other.sqlHandlingMode &&
            resultSetCount == other.resultSetCount &&
            selectedResultSetIndex == other.selectedResultSetIndex &&
            hasMultipleResultSets == other.hasMultipleResultSets &&
            identical(results, other.results) &&
            identical(columnMetadata, other.columnMetadata);
  }

  @override
  int get hashCode => Object.hashAll([
    results,
    isLoading,
    isStreaming,
    rowsProcessed,
    progress,
    executionDuration,
    affectedRows,
    columnMetadata,
    error,
    currentPage,
    pageSize,
    hasNextPage,
    hasPreviousPage,
    hasPagination,
    sqlHandlingMode,
    resultSetCount,
    selectedResultSetIndex,
    hasMultipleResultSets,
  ]);
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
