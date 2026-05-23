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
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_page_editor.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_actions_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_history_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_selected_detail.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_settings_tab.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_status_strip.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_definition_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_details_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_remote_audit_panel.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
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
  int _selectedTabIndex = 0;
  bool _restoredUiPreferences = false;
  bool _isActionEditorDialogPendingOrOpen = false;
  late final AgentActionsUiPreferences _uiPreferences;

  @override
  void initState() {
    super.initState();
    _uiPreferences = AgentActionsUiPreferences(() => widget.appSettingsStore);
    _selectedTabIndex = _uiPreferences.readSelectedTabIndex() ?? 0;
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
      content: Consumer<AgentActionsProvider>(
        builder: (context, provider, _) {
          return widgets.CallbackShortcuts(
            bindings: <widgets.ShortcutActivator, VoidCallback>{
              const widgets.SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
                _runPageShortcut(() {
                  if (provider.canSaveAction) {
                    _scheduleActionEditorDialog(context, provider, l10n);
                  }
                });
              },
              const widgets.SingleActivator(LogicalKeyboardKey.enter): () {
                _runPageShortcut(() => _editSelectedAction(context, provider, l10n));
              },
              const widgets.SingleActivator(LogicalKeyboardKey.delete): () {
                _runPageShortcut(() => _deleteSelectedAction(context, provider, l10n));
              },
              const widgets.SingleActivator(LogicalKeyboardKey.f5): () {
                _runPageShortcut(() => unawaited(provider.load()));
              },
              const widgets.SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
                _runPageShortcut(() {
                  if (provider.canTestSelected) {
                    unawaited(provider.testSelectedAction());
                  }
                });
              },
              const widgets.SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
                _runPageShortcut(() {
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
                    AgentActionsStatusStrip(
                      provider: provider,
                      l10n: l10n,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: provider.isFeatureEnabled
                          ? _buildTabs(
                              context: context,
                              provider: provider,
                              l10n: l10n,
                              runtimeCapabilities: widget.runtimeCapabilities,
                              runtimeDiagnostics: widget.runtimeDiagnostics,
                            )
                          : AppCard(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Text(
                                    l10n.agentActionsDisabledMessage,
                                    style: context.bodyMuted,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
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
          body: AgentActionsRemoteAuditPanel(provider: provider, l10n: l10n),
        ),
    ];
    final safeIndex = _selectedTabIndex.clamp(0, items.length - 1);

    return AppFluentTabView(
      currentIndex: safeIndex,
      onChanged: _handleTabChanged,
      items: items,
    );
  }

  void _handleTabChanged(int index) {
    setState(() => _selectedTabIndex = index);
    unawaited(_uiPreferences.persistSelectedTabIndex(index));
  }

  void _restoreProviderUiPreferences(AgentActionsProvider provider) {
    if (_restoredUiPreferences) {
      return;
    }
    _restoredUiPreferences = true;
    _uiPreferences.restoreInto(provider);
  }

  void _runPageShortcut(VoidCallback action) {
    if (_isTextInputFocused()) {
      return;
    }
    action();
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AgentActionDefinitionDialog(
          child: DeferredAgentActionEditor(
            provider: provider,
            definition: definition,
            l10n: l10n,
            onSaved: () {
              Navigator.pop(dialogContext);
            },
          ),
        );
      },
    );
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
