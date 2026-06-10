import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_actions_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_history_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_selected_detail.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_settings_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_status_strip.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_deferred.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_details_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_remote_audit_panel.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_confirm_dialog.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_content_dialog.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class AgentActionsPage extends StatefulWidget {
  const AgentActionsPage({
    required this.runtimeCapabilities,
    required this.appSettingsStore,
    this.runtimeDiagnostics,
    super.key,
  });

  final RuntimeCapabilities runtimeCapabilities;
  final RuntimeDetectionDiagnostics? runtimeDiagnostics;
  final IAppSettingsStore appSettingsStore;

  @override
  State<AgentActionsPage> createState() => _AgentActionsPageState();
}

class _AgentActionsPageState extends State<AgentActionsPage> {
  AgentActionsTab _selectedTab = AgentActionsTab.actions;
  bool _restoredUiPreferences = false;
  bool _isActionEditorDialogPendingOrOpen = false;
  late final AgentActionsUiPreferences _uiPreferences;

  @override
  void initState() {
    super.initState();
    _uiPreferences = AgentActionsUiPreferences(() => widget.appSettingsStore);
    _selectedTab = _uiPreferences.readSelectedTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final provider = context.read<AgentActionsProvider>();
      _restoreProviderUiPreferences(provider);
      unawaited(provider.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navAgentActions,
          style: context.sectionTitle,
        ),
      ),
      content: widgets.CallbackShortcuts(
        bindings: <widgets.ShortcutActivator, VoidCallback>{
          const widgets.SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            _runActionsTabShortcut(() {
              final provider = context.read<AgentActionsProvider>();
              if (provider.canSaveAction) {
                _scheduleActionEditorDialog(context, provider, l10n);
              }
            });
          },
          const widgets.SingleActivator(LogicalKeyboardKey.enter): () {
            _runActionsTabShortcut(
              () => _editSelectedAction(context, context.read<AgentActionsProvider>(), l10n),
            );
          },
          const widgets.SingleActivator(LogicalKeyboardKey.delete): () {
            _runActionsTabShortcut(
              () => _deleteSelectedAction(context, context.read<AgentActionsProvider>(), l10n),
            );
          },
          const widgets.SingleActivator(LogicalKeyboardKey.f5): () {
            _runPageShortcut(() => unawaited(context.read<AgentActionsProvider>().load()));
          },
          const widgets.SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            _runActionsTabShortcut(() {
              final provider = context.read<AgentActionsProvider>();
              if (provider.canTestSelected) {
                unawaited(provider.testSelectedAction());
              }
            });
          },
          const widgets.SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
            _runActionsTabShortcut(() {
              final provider = context.read<AgentActionsProvider>();
              if (provider.canRunSelected) {
                unawaited(
                  runAgentActionWithDangerousCommandCheck(
                    context,
                    provider,
                    l10n,
                  ),
                );
              }
            });
          },
        },
        child: widgets.Focus(
          autofocus: true,
          child: Padding(
            padding: AppLayout.pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Selector<AgentActionsProvider, int>(
                  selector: (_, provider) => Object.hash(
                    provider.isFeatureEnabled,
                    provider.isLoading,
                    provider.errorMessage,
                    provider.runtimeSubsystemSnapshot,
                    provider.shouldWarnComObjectHandlersMissing,
                    provider.triggerErrorMessage,
                  ),
                  builder: (context, _, child) {
                    return AgentActionsStatusStrip(
                      provider: context.read<AgentActionsProvider>(),
                      l10n: l10n,
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: Selector<AgentActionsProvider, bool>(
                    selector: (_, provider) => provider.isFeatureEnabled,
                    builder: (context, isFeatureEnabled, _) {
                      if (!isFeatureEnabled) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: InfoBar(
                            title: Text(l10n.agentActionsDisabledTitle),
                            content: Text(l10n.agentActionsDisabledMessage),
                            severity: InfoBarSeverity.warning,
                            isLong: true,
                          ),
                        );
                      }

                      return Selector<AgentActionsProvider, bool>(
                        selector: (_, provider) => provider.isRemoteAuditSectionVisible,
                        builder: (context, _, child) {
                          return _buildTabs(
                            context: context,
                            provider: context.read<AgentActionsProvider>(),
                            l10n: l10n,
                            runtimeCapabilities: widget.runtimeCapabilities,
                            runtimeDiagnostics: widget.runtimeDiagnostics,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs({
    required BuildContext context,
    required AgentActionsProvider provider,
    required AppLocalizations l10n,
    required RuntimeCapabilities runtimeCapabilities,
    required RuntimeDetectionDiagnostics? runtimeDiagnostics,
  }) {
    final items = [
      AppFluentTabItem(
        icon: FluentIcons.processing,
        text: l10n.agentActionsSummaryActions,
        body: AgentActionsActionsTab(
          provider: provider,
          l10n: l10n,
          uiPreferences: _uiPreferences,
          onCreateAction: () => _scheduleActionEditorDialog(context, provider, l10n),
          onShowDetails: (definition) => _showActionDetailsDialog(
            context,
            provider,
            l10n,
            definition,
          ),
          onEditAction: (definition) => _scheduleActionEditorDialog(
            context,
            provider,
            l10n,
            definition: definition,
          ),
        ),
      ),
      AppFluentTabItem(
        icon: FluentIcons.history,
        text: l10n.agentActionsHistoryTitle,
        body: AgentActionsHistoryTab(provider: provider, l10n: l10n, uiPreferences: _uiPreferences),
      ),
      AppFluentTabItem(
        icon: FluentIcons.settings,
        text: l10n.configTabPreferences,
        body: AgentActionsSettingsTab(
          provider: provider,
          l10n: l10n,
          runtimeCapabilities: runtimeCapabilities,
          runtimeDiagnostics: runtimeDiagnostics,
        ),
      ),
      if (provider.isRemoteAuditSectionVisible)
        AppFluentTabItem(
          icon: FluentIcons.cloud,
          text: l10n.agentActionsRemoteAuditTitle,
          body: AgentActionsRemoteAuditPanel(
            provider: provider,
            l10n: l10n,
            onShowInHistory: () => _handleTabChanged(AgentActionsTab.history),
          ),
        ),
    ];
    final tabOrder = [
      AgentActionsTab.actions,
      AgentActionsTab.history,
      AgentActionsTab.settings,
      if (provider.isRemoteAuditSectionVisible) AgentActionsTab.remoteAudit,
    ];
    var currentIndex = tabOrder.indexOf(_selectedTab);
    if (currentIndex < 0) {
      currentIndex = 0;
    }

    return AppFluentTabView(
      currentIndex: currentIndex,
      onChanged: (index) => _handleTabChanged(tabOrder[index]),
      items: items,
    );
  }

  void _handleTabChanged(AgentActionsTab tab) {
    setState(() => _selectedTab = tab);
    unawaited(_uiPreferences.persistSelectedTab(tab));
  }

  void _restoreProviderUiPreferences(AgentActionsProvider provider) {
    if (_restoredUiPreferences) {
      return;
    }
    _restoredUiPreferences = true;
    _uiPreferences.restoreInto(provider);
  }

  void _runPageShortcut(VoidCallback action) {
    if (_isTextInputFocused() || _isActionEditorDialogPendingOrOpen) {
      return;
    }
    action();
  }

  /// Shortcut that only fires when the user is on the actions tab, to avoid
  /// accidentally editing or deleting an action while looking at history or
  /// settings.
  void _runActionsTabShortcut(VoidCallback action) {
    if (_selectedTab != AgentActionsTab.actions) {
      return;
    }
    _runPageShortcut(action);
  }

  bool _isTextInputFocused() {
    final focusedContext = widgets.FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is widgets.EditableText ||
        focusedContext.findAncestorWidgetOfExactType<widgets.EditableText>() != null;
  }

  void _editSelectedAction(
    BuildContext context,
    AgentActionsProvider provider,
    AppLocalizations l10n,
  ) {
    final definition = provider.selectedDefinition;
    if (definition == null || !isAgentActionTypeEditableInUi(definition.type)) {
      return;
    }
    _scheduleActionEditorDialog(context, provider, l10n, definition: definition);
  }

  void _deleteSelectedAction(
    BuildContext context,
    AgentActionsProvider provider,
    AppLocalizations l10n,
  ) {
    final definition = provider.selectedDefinition;
    if (definition == null || !provider.canDeleteSelected) {
      return;
    }
    unawaited(confirmAgentActionDelete(context, provider, definition, l10n));
  }

  Future<void> _showActionEditorDialog(
    BuildContext context,
    AgentActionsProvider provider,
    AppLocalizations l10n, {
    AgentActionDefinition? definition,
  }) async {
    final dirtyNotifier = ValueNotifier<bool>(false);
    try {
      // Fluent's showDialog already defaults to barrierDismissible: false,
      // so accidental clicks outside the editor do not drop the draft.
      // The close button and Esc go through _confirmEditorClose below.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _AgentActionEditorDialogShell(
            l10n: l10n,
            dirtyNotifier: dirtyNotifier,
            child: DeferredAgentActionEditor(
              provider: provider,
              definition: definition,
              l10n: l10n,
              dirtyNotifier: dirtyNotifier,
              onSaved: () {
                Navigator.pop(dialogContext);
              },
            ),
          );
        },
      );
    } finally {
      dirtyNotifier.dispose();
    }
  }

  void _scheduleActionEditorDialog(
    BuildContext context,
    AgentActionsProvider provider,
    AppLocalizations l10n, {
    AgentActionDefinition? definition,
  }) {
    if (_isActionEditorDialogPendingOrOpen) {
      return;
    }
    _isActionEditorDialogPendingOrOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) {
        _isActionEditorDialogPendingOrOpen = false;
        return;
      }
      unawaited(
        _showActionEditorDialog(
          context,
          provider,
          l10n,
          definition: definition,
        ).whenComplete(() {
          _isActionEditorDialogPendingOrOpen = false;
        }),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _showActionDetailsDialog(
    BuildContext context,
    AgentActionsProvider provider,
    AppLocalizations l10n,
    AgentActionDefinition definition,
  ) async {
    provider.selectAction(definition.id);
    await provider.refreshTriggersForSelection();
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AgentActionDetailsDialog(
          definition: definition,
          l10n: l10n,
          content: ListenableBuilder(
            listenable: provider,
            builder: (context, _) {
              final selected = provider.selectedDefinition;
              if (selected == null) {
                return Center(
                  child: Text(
                    l10n.agentActionsEmptySelection,
                    style: context.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView(
                key: AgentActionsPageKeys.detailScroll,
                children: [
                  AgentActionSelectedDetailContent(
                    provider: provider,
                    l10n: l10n,
                    definition: selected,
                    lastTestCanRun: provider.lastTestCanRun ?? false,
                    onEditAction: (definition) {
                      Navigator.pop(dialogContext);
                      _scheduleActionEditorDialog(
                        context,
                        provider,
                        l10n,
                        definition: definition,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Wraps the action editor dialog with a discard-confirmation guard.
///
/// Without this, closing the dialog (Esc, close button) when the form has
/// unsaved changes would silently drop everything the user typed.
class _AgentActionEditorDialogShell extends StatelessWidget {
  const _AgentActionEditorDialogShell({
    required this.l10n,
    required this.dirtyNotifier,
    required this.child,
  });

  final AppLocalizations l10n;
  final ValueNotifier<bool> dirtyNotifier;
  final Widget child;

  Future<bool> _confirmClose(BuildContext context) async {
    if (!dirtyNotifier.value) {
      return true;
    }
    return AppConfirmDialog.show(
      context: context,
      title: l10n.agentActionsEditorDiscardConfirmTitle,
      message: l10n.agentActionsEditorDiscardConfirmMessage,
      confirmLabel: l10n.agentActionsEditorDiscardConfirm,
      cancelLabel: l10n.agentActionsEditorKeepEditing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dirtyNotifier,
      builder: (_, isDirty, _) {
        return widgets.PopScope<Object?>(
          canPop: !isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              return;
            }
            final navigator = Navigator.of(context);
            final confirmed = await _confirmClose(context);
            if (confirmed && navigator.mounted) {
              navigator.pop();
            }
          },
          child: AppContentDialog(
            maxWidth: 980,
            maxHeight: 760,
            contentWidth: 920,
            contentHeight: 680,
            closeTooltip: l10n.btnClose,
            title: const SizedBox.shrink(),
            onClose: () async {
              final navigator = Navigator.of(context);
              final confirmed = await _confirmClose(context);
              if (confirmed && navigator.mounted) {
                navigator.pop();
              }
            },
            content: child,
          ),
        );
      },
    );
  }
}
