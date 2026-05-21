import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_failure_phase_filter_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_secrets_section.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_detail_panel.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_master_detail_layout.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_remote_audit_panel.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_retention_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_runtime_support_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_summary_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_toolbar_card.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class _AgentActionsPageKeys {
  static const ValueKey<String> detailScroll = ValueKey<String>('agent_actions_detail_scroll');
  static const ValueKey<String> historyList = ValueKey<String>('agent_actions_history_list');
  static const ValueKey<String> testPreview = ValueKey<String>('agent_actions_test_preview');
  static const ValueKey<String> remoteReapprovalInfoBar = ValueKey<String>('agent_actions_remote_reapproval_info_bar');
  static const ValueKey<String> developerConnectionMissingInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_missing_info_bar',
  );
  static const ValueKey<String> developerConnectionUnknownInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_unknown_info_bar',
  );
  static const ValueKey<String> developerConnectionChangedInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_changed_info_bar',
  );

  static ValueKey<String> executionSupportCopyButton(String executionId) {
    return ValueKey<String>('execution_support_copy_button_$executionId');
  }
}

class AgentActionsPage extends StatefulWidget {
  const AgentActionsPage({super.key});

  @override
  State<AgentActionsPage> createState() => _AgentActionsPageState();
}

class _AgentActionsPageState extends State<AgentActionsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(context.read<AgentActionsProvider>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final runtimeCapabilities = getIt<RuntimeCapabilities>();
    final runtimeDiagnostics = getIt.isRegistered<RuntimeDetectionDiagnostics>()
        ? getIt<RuntimeDetectionDiagnostics>()
        : null;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navAgentActions,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: Consumer<AgentActionsProvider>(
          builder: (context, provider, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AgentActionsToolbarCard(provider: provider, l10n: l10n),
                        const SizedBox(height: AppSpacing.md),
                        if (!provider.isFeatureEnabled) ...[
                          InfoBar(
                            title: Text(l10n.agentActionsDisabledTitle),
                            content: Text(l10n.agentActionsDisabledMessage),
                            severity: InfoBarSeverity.warning,
                            isLong: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (provider.isFeatureEnabled && provider.isMaintenanceMode) ...[
                          InfoBar(
                            title: Text(l10n.agentActionsMaintenanceModeInfoTitle),
                            content: Text(l10n.agentActionsMaintenanceModeInfoMessage),
                            isLong: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        ..._elevatedRunnerStatusWidgets(provider, l10n),
                        ..._runtimeSubsystemStatusWidgets(provider, l10n),
                        ..._schedulerOperationalIssueWidgets(provider, l10n),
                        ..._comObjectInvocationWarningWidgets(provider, l10n),
                        if (provider.errorMessage != null) ...[
                          InfoBar(
                            title: Text(l10n.agentActionsErrorTitle),
                            content: SelectableText(provider.errorMessage!),
                            severity: InfoBarSeverity.error,
                            isLong: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        AgentActionsSummaryCard(provider: provider, l10n: l10n),
                        if (provider.isFeatureEnabled) ...[
                          const SizedBox(height: AppSpacing.md),
                          AgentActionsRetentionCard(l10n: l10n),
                        ],
                        if (runtimeCapabilities.isDegraded ||
                            runtimeCapabilities.isUnsupported ||
                            runtimeDiagnostics?.source == RuntimeDetectionSource.detectionFailed) ...[
                          const SizedBox(height: AppSpacing.md),
                          AgentActionsRuntimeSupportCard(
                            capabilities: runtimeCapabilities,
                            diagnostics: runtimeDiagnostics,
                          ),
                        ],
                        if (provider.isRemoteAuditSectionVisible) ...[
                          const SizedBox(height: AppSpacing.md),
                          AgentActionsRemoteAuditPanel(provider: provider, l10n: l10n),
                        ],
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: provider.isFeatureEnabled
                      ? AgentActionsMasterDetailLayout(
                          master: _AgentActionsList(provider: provider, l10n: l10n),
                          detail: _AgentActionsDetail(provider: provider, l10n: l10n),
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
            );
          },
        ),
      ),
    );
  }
}

List<Widget> _comObjectInvocationWarningWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.shouldWarnComObjectHandlersMissing) {
    return const <Widget>[];
  }

  return <Widget>[
    InfoBar(
      key: const ValueKey<String>('agent_actions_com_object_handlers_missing'),
      title: Text(l10n.agentActionsComObjectHandlersMissingTitle),
      content: Text(l10n.agentActionsComObjectHandlersMissingMessage),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> _schedulerOperationalIssueWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isFeatureEnabled) {
    return const <Widget>[];
  }

  final reason = provider.schedulerOperationalIssueReason;
  if (reason == null) {
    return const <Widget>[];
  }

  final message = switch (reason) {
    AgentActionTriggerConstants.schedulerInstanceLockedReason => l10n.agentActionsSchedulerInstanceLockedMessage,
    AgentActionTriggerConstants.schedulerBootstrapFailedReason => l10n.agentActionsSchedulerBootstrapFailedMessage,
    _ => null,
  };
  if (message == null) {
    return const <Widget>[];
  }

  return <Widget>[
    InfoBar(
      key: const ValueKey<String>('agent_actions_scheduler_operational_issue'),
      title: Text(l10n.agentActionsSchedulerOperationalIssueTitle),
      content: Text(message),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> _runtimeSubsystemStatusWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isFeatureEnabled) {
    return const <Widget>[];
  }

  final bar = _runtimeSubsystemInfoBar(provider, l10n);
  if (bar == null) {
    return const <Widget>[];
  }

  return <Widget>[
    bar,
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> _elevatedRunnerStatusWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isElevatedAgentActionsEnabled) {
    return const <Widget>[];
  }

  final widgets = <Widget>[];
  if (provider.isElevatedRunnerDegraded) {
    widgets.add(
      InfoBar(
        title: Text(l10n.agentActionsElevatedRunnerDegradedTitle),
        content: Text(l10n.agentActionsElevatedRunnerDegradedMessage),
        severity: InfoBarSeverity.warning,
        isLong: true,
        action: Button(
          onPressed: provider.isPreparingElevatedRunner
              ? null
              : () {
                  unawaited(provider.prepareElevatedRunner());
                },
          child: Text(
            provider.isPreparingElevatedRunner
                ? l10n.agentActionsElevatedRunnerPreparing
                : l10n.agentActionsElevatedRunnerPrepare,
          ),
        ),
      ),
    );
  } else if (!provider.isElevatedRunnerConfigured) {
    widgets.add(
      InfoBar(
        title: Text(l10n.agentActionsElevatedRunnerNotReadyTitle),
        content: Text(l10n.agentActionsElevatedRunnerNotReadyMessage),
        severity: InfoBarSeverity.warning,
        isLong: true,
        action: Button(
          onPressed: provider.isPreparingElevatedRunner
              ? null
              : () {
                  unawaited(provider.prepareElevatedRunner());
                },
          child: Text(
            provider.isPreparingElevatedRunner
                ? l10n.agentActionsElevatedRunnerPreparing
                : l10n.agentActionsElevatedRunnerPrepare,
          ),
        ),
      ),
    );
  }

  if (widgets.isEmpty) {
    return const <Widget>[];
  }

  return <Widget>[
    ...widgets,
    const SizedBox(height: AppSpacing.md),
  ];
}

Widget? _runtimeSubsystemInfoBar(AgentActionsProvider provider, AppLocalizations l10n) {
  final snapshot = provider.runtimeSubsystemSnapshot;
  return switch (snapshot.status) {
    AgentActionSubsystemStatus.ready || AgentActionSubsystemStatus.maintenance => null,
    AgentActionSubsystemStatus.starting => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusStartingTitle),
      content: Text(l10n.agentActionsSubsystemStatusStartingMessage),
      isLong: true,
    ),
    AgentActionSubsystemStatus.draining => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDrainingTitle),
      content: Text(l10n.agentActionsSubsystemStatusDrainingMessage),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    AgentActionSubsystemStatus.degraded => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDegradedTitle),
      content: Text(
        l10n.agentActionsSubsystemStatusDegradedMessage(
          snapshot.unavailableActionTypes.map((AgentActionType type) => type.name).join(', '),
        ),
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    AgentActionSubsystemStatus.disabled => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDisabledTitle),
      content: Text(l10n.agentActionsSubsystemStatusDisabledMessage),
      severity: InfoBarSeverity.error,
      isLong: true,
    ),
  };
}

class _AgentActionsList extends StatelessWidget {
  const _AgentActionsList({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const Center(child: ProgressRing());
    }
    if (provider.definitions.isEmpty) {
      return AppCard(
        child: Center(
          child: Text(
            l10n.agentActionsEmptyActions,
            style: context.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final visibleDefinitions = provider.filteredDefinitions;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: _AgentActionsDefinitionFilters(provider: provider, l10n: l10n),
          ),
          if (visibleDefinitions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l10n.agentActionsListFilterEmpty,
                style: context.bodyMuted,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...visibleDefinitions.map((definition) {
              final selected = provider.selectedActionId == definition.id;
              final riskDescriptors = collectAgentActionRiskDescriptors(
                definition: definition,
                l10n: l10n,
                runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
                editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
                needsValidation: definition.state == AgentActionState.needsValidation,
                secretPlaceholderNames: definition.id == provider.selectedActionId
                    ? provider.selectedSecretPlaceholderNames
                    : AgentActionSecretPlaceholderScanner.collectFromDefinition(definition),
                triggers: definition.id == provider.selectedActionId ? provider.triggers : const <AgentActionTrigger>[],
              );
              return ListTile.selectable(
                selected: selected,
                leading: Icon(_iconFor(definition.type)),
                title: Text(definition.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_actionSubtitle(definition, l10n)),
                    if (riskDescriptors.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AgentActionRiskChips(descriptors: riskDescriptors),
                    ],
                  ],
                ),
                onPressed: () => provider.selectAction(definition.id),
              );
            }),
        ],
      ),
    );
  }
}

class _AgentActionsDefinitionFilters extends StatefulWidget {
  const _AgentActionsDefinitionFilters({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  State<_AgentActionsDefinitionFilters> createState() => _AgentActionsDefinitionFiltersState();
}

class _AgentActionsDefinitionFiltersState extends State<_AgentActionsDefinitionFilters> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.provider.definitionSearchQuery);
  }

  @override
  void didUpdateWidget(covariant _AgentActionsDefinitionFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.provider.definitionSearchQuery;
    if (query != _searchController.text) {
      _searchController.text = query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final l10n = widget.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionType?>(
            label: l10n.agentActionsListFilterType,
            value: provider.definitionTypeFilter,
            items: [
              ComboBoxItem<AgentActionType?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionType.values.map(
                (type) => ComboBoxItem<AgentActionType?>(
                  value: type,
                  child: Text(_typeLabel(type, l10n)),
                ),
              ),
            ],
            onChanged: provider.setDefinitionTypeFilter,
          ),
        ),
        SizedBox(
          width: 220,
          child: AppTextField(
            label: l10n.agentActionsListFilterSearch,
            controller: _searchController,
            onChanged: provider.setDefinitionSearchQuery,
            textInputAction: TextInputAction.search,
          ),
        ),
      ],
    );
  }
}

class _AgentActionsDetail extends StatelessWidget {
  const _AgentActionsDetail({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final selected = provider.selectedDefinition;
    if (selected == null) {
      return AgentActionsEmptySelectionPanel(
        detailScrollKey: _AgentActionsPageKeys.detailScroll,
        content: Column(
          children: [
            Text(
              l10n.agentActionsEmptySelection,
              style: context.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            _AgentActionEditor(
              provider: provider,
              l10n: l10n,
            ),
          ],
        ),
      );
    }

    final executions = provider.filteredSelectedExecutions;
    final lastTestCanRun = provider.lastTestCanRun ?? false;
    return AgentActionsDetailPanel(
      detailScrollKey: _AgentActionsPageKeys.detailScroll,
      historyListKey: _AgentActionsPageKeys.historyList,
      emptySelectionContent: const SizedBox.shrink(),
      selectionContent: _SelectedActionDetailContent(
        provider: provider,
        l10n: l10n,
        definition: selected,
        lastTestCanRun: lastTestCanRun,
      ),
      historyTitle: Text(l10n.agentActionsHistoryTitle, style: context.sectionTitle),
      historyFilters: _AgentActionsHistoryFilters(provider: provider, l10n: l10n),
      historyList: _AgentActionExecutionList(
        executions: executions,
        provider: provider,
        l10n: l10n,
        shrinkWrap: true,
      ),
    );
  }
}

class _SelectedActionDetailContent extends StatelessWidget {
  const _SelectedActionDetailContent({
    required this.provider,
    required this.l10n,
    required this.definition,
    required this.lastTestCanRun,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionDefinition definition;
  final bool lastTestCanRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_iconFor(definition.type), size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(definition.name, style: context.sectionTitle)),
            Text(_stateLabel(definition.state, l10n), style: context.bodyMuted),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: l10n.agentActionsDeleteSelected,
              child: Semantics(
                button: true,
                label: l10n.agentActionsDeleteSelected,
                child: IconButton(
                  icon: provider.isDeleting
                      ? const SizedBox.square(
                          dimension: 14,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.delete),
                  onPressed: provider.canDeleteSelected
                      ? () {
                          unawaited(
                            _confirmDelete(
                              context,
                              provider,
                              definition,
                              l10n,
                            ),
                          );
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (provider.lastTestedActionId == definition.id) ...[
          InfoBar(
            title: Text(l10n.agentActionsTestSuccessTitle),
            content: Text(
              lastTestCanRun ? l10n.agentActionsTestCanRunMessage : l10n.agentActionsTestValidButInactiveMessage,
            ),
            severity: lastTestCanRun ? InfoBarSeverity.success : InfoBarSeverity.info,
            isLong: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _AgentActionTestPreview(
            provider: provider,
            l10n: l10n,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _Pill(text: _typeLabel(definition.type, l10n)),
            _Pill(text: definition.id),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AgentActionRiskChips(
          key: ValueKey<String>('agent_action_risk_chips_${definition.id}'),
          descriptors: collectAgentActionRiskDescriptors(
            definition: definition,
            l10n: l10n,
            runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
            editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
            needsValidation: definition.state == AgentActionState.needsValidation,
            secretPlaceholderNames: provider.selectedSecretPlaceholderNames,
            triggers: provider.triggers,
          ),
        ),
        if (definition.state == AgentActionState.needsValidation) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsNeedsValidationTitle),
            content: Text(l10n.agentActionsNeedsValidationMessage),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        if (!isAgentActionTypeEditableInUi(definition.type)) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsValidationTitle),
            content: Text(l10n.agentActionsFormUnsupportedType),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        if (provider.isActionSecretStoreAvailable && provider.selectedSecretPlaceholderNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AgentActionSecretsSection(
            key: ValueKey<String>('agent_action_secrets_${definition.id}'),
            provider: provider,
            l10n: l10n,
          ),
        ] else ...[
          if (provider.selectedSecretPlaceholderNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsSecretPlaceholdersTitle),
              content: Text(
                l10n.agentActionsSecretPlaceholdersMessage(
                  provider.selectedSecretPlaceholderNames.join(', '),
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          if (provider.selectedMissingSecretNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsMissingSecretsTitle),
              content: Text(
                l10n.agentActionsMissingSecretsMessage(
                  provider.selectedMissingSecretNames.join(', '),
                ),
              ),
              severity: InfoBarSeverity.error,
              isLong: true,
            ),
          ],
        ],
        if (provider.secretOperationErrorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsSecretOperationErrorTitle),
            content: SelectableText(provider.secretOperationErrorMessage!),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ],
        if (provider.isActionTypeUnavailable(definition.type)) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsActionTypeUnavailableTitle),
            content: Text(
              l10n.agentActionsActionTypeUnavailableMessage(
                _typeLabel(definition.type, l10n),
              ),
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _AgentActionEditor(
          provider: provider,
          definition: definition,
          l10n: l10n,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(l10n.agentActionsTriggersTitle, style: context.sectionTitle),
            ),
            Button(
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.clearTriggerOperationError();
                      unawaited(
                        showAgentActionTriggerSaveDialog(
                          context: context,
                          provider: provider,
                          l10n: l10n,
                          actionId: definition.id,
                        ),
                      );
                    }
                  : null,
              child: Text(l10n.agentActionsTriggerAdd),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _AgentActionTriggersSection(
          provider: provider,
          l10n: l10n,
          actionId: definition.id,
        ),
      ],
    );
  }
}

class _AgentActionExecutionList extends StatelessWidget {
  const _AgentActionExecutionList({
    required this.executions,
    required this.provider,
    required this.l10n,
    this.shrinkWrap = false,
  });

  final List<AgentActionExecution> executions;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (executions.isEmpty) {
      return Center(
        child: Text(
          l10n.agentActionsEmptyHistory,
          style: context.bodyMuted,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: executions.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final execution = executions[index];
        return _ExecutionRow(
          execution: execution,
          provider: provider,
          l10n: l10n,
        );
      },
    );
  }
}

class _AgentActionTriggersSection extends StatelessWidget {
  const _AgentActionTriggersSection({
    required this.provider,
    required this.l10n,
    required this.actionId,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingTriggers) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.agentActionsTriggersLoading,
              style: context.bodyMuted,
            ),
          ),
        ],
      );
    }

    if (provider.triggers.isEmpty) {
      return Text(
        l10n.agentActionsTriggersEmpty,
        style: context.bodyMuted,
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        itemCount: provider.triggers.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (BuildContext context, int index) {
          final trigger = provider.triggers[index];
          return _AgentActionTriggerRow(
            trigger: trigger,
            provider: provider,
            l10n: l10n,
            actionId: actionId,
          );
        },
      ),
    );
  }
}

class _AgentActionTriggerRow extends StatelessWidget {
  const _AgentActionTriggerRow({
    required this.trigger,
    required this.provider,
    required this.l10n,
    required this.actionId,
  });

  final AgentActionTrigger trigger;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;

  @override
  Widget build(BuildContext context) {
    final title = _triggerDisplayTitle(trigger, l10n);
    final summary = _triggerSummaryLine(trigger, l10n);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                trigger.id,
                style: context.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                summary,
                style: context.bodyMuted,
              ),
            ],
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTriggerEdit,
          child: Semantics(
            button: true,
            label: l10n.agentActionsTriggerEdit,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.clearTriggerOperationError();
                      unawaited(
                        showAgentActionTriggerSaveDialog(
                          context: context,
                          provider: provider,
                          l10n: l10n,
                          actionId: actionId,
                          existing: trigger,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTriggerDelete,
          child: Semantics(
            button: true,
            label: l10n.agentActionsTriggerDelete,
            child: IconButton(
              icon: provider.isDeletingTrigger(trigger.id)
                  ? const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.delete),
              onPressed: provider.isFeatureEnabled && !provider.isDeletingTrigger(trigger.id)
                  ? () {
                      unawaited(
                        _confirmDeleteTrigger(
                          context,
                          provider,
                          trigger,
                          l10n,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteTrigger(
  BuildContext context,
  AgentActionsProvider provider,
  AgentActionTrigger trigger,
  AppLocalizations l10n,
) async {
  final label = _triggerDeleteConfirmLabel(trigger, l10n);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: Text(l10n.agentActionsTriggerDeleteConfirmTitle),
        content: Text(l10n.agentActionsTriggerDeleteConfirmMessage(label)),
        actions: [
          Button(
            child: Text(l10n.agentActionsTriggerDeleteCancel),
            onPressed: () {
              Navigator.pop(context, false);
            },
          ),
          FilledButton(
            child: Text(l10n.agentActionsTriggerDeleteConfirm),
            onPressed: () {
              Navigator.pop(context, true);
            },
          ),
        ],
      );
    },
  );

  if (confirmed ?? false) {
    await provider.deleteTrigger(trigger.id);
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  AgentActionsProvider provider,
  AgentActionDefinition definition,
  AppLocalizations l10n,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: Text(l10n.agentActionsDeleteConfirmTitle),
        content: Text(l10n.agentActionsDeleteConfirmMessage(definition.name)),
        actions: [
          Button(
            child: Text(l10n.agentActionsDeleteCancel),
            onPressed: () {
              Navigator.pop(context, false);
            },
          ),
          FilledButton(
            child: Text(l10n.agentActionsDeleteConfirm),
            onPressed: () {
              Navigator.pop(context, true);
            },
          ),
        ],
      );
    },
  );

  if (confirmed ?? false) {
    await provider.deleteSelectedAction();
  }
}

class _AgentActionsHistoryFilters extends StatefulWidget {
  const _AgentActionsHistoryFilters({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  State<_AgentActionsHistoryFilters> createState() => _AgentActionsHistoryFiltersState();
}

class _AgentActionsHistoryFiltersState extends State<_AgentActionsHistoryFilters> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.provider.historySearchQuery);
  }

  @override
  void didUpdateWidget(covariant _AgentActionsHistoryFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.provider.historySearchQuery;
    if (query != _searchController.text) {
      _searchController.text = query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final l10n = widget.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionExecutionStatus?>(
            label: l10n.agentActionsHistoryFilterStatus,
            value: provider.historyStatusFilter,
            items: [
              ComboBoxItem<AgentActionExecutionStatus?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionExecutionStatus.values.map(
                (status) => ComboBoxItem<AgentActionExecutionStatus?>(
                  value: status,
                  child: Text(_statusLabel(status, l10n)),
                ),
              ),
            ],
            onChanged: provider.setHistoryStatusFilter,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionRequestSource?>(
            label: l10n.agentActionsHistoryFilterSource,
            value: provider.historySourceFilter,
            items: [
              ComboBoxItem<AgentActionRequestSource?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionRequestSource.values.map(
                (source) => ComboBoxItem<AgentActionRequestSource?>(
                  value: source,
                  child: Text(_sourceLabel(source, l10n)),
                ),
              ),
            ],
            onChanged: provider.setHistorySourceFilter,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionHistoryPeriod>(
            label: l10n.agentActionsHistoryFilterPeriod,
            value: provider.historyPeriodFilter,
            items: AgentActionHistoryPeriod.values
                .map(
                  (period) => ComboBoxItem<AgentActionHistoryPeriod>(
                    value: period,
                    child: Text(_periodLabel(period, l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: (period) {
              if (period == null) {
                return;
              }
              provider.setHistoryPeriodFilter(period);
            },
          ),
        ),
        SizedBox(
          width: 210,
          child: AppDropdown<String?>(
            label: l10n.agentActionsHistoryFilterFailurePhase,
            value: provider.historyFailurePhaseFilter,
            items: [
              ComboBoxItem<String?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionFailurePhaseFilterConstants.historyFilterPhases.map(
                (phase) => ComboBoxItem<String?>(
                  value: phase,
                  child: Text(_localizedFailurePhase(phase, l10n)),
                ),
              ),
            ],
            onChanged: provider.setHistoryFailurePhaseFilter,
          ),
        ),
        SizedBox(
          width: 280,
          child: AppTextField(
            label: l10n.agentActionsHistoryFilterSearch,
            controller: _searchController,
            onChanged: provider.setHistorySearchQuery,
            textInputAction: TextInputAction.search,
          ),
        ),
      ],
    );
  }
}

class _AgentActionEditor extends StatefulWidget {
  const _AgentActionEditor({
    required this.provider,
    required this.l10n,
    this.definition,
  });

  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;

  @override
  State<_AgentActionEditor> createState() => _AgentActionEditorState();
}

class _AgentActionEditorState extends State<_AgentActionEditor> {
  static const String _defaultDeveloperExecutorPath = r'C:\Data7\bin\Executor.exe';
  static const String _defaultDeveloperConfigBinPath = r'C:\Data7\bin\Data7.Config';
  static const String _defaultDeveloperConfigRootPath = r'C:\Data7\Data7.Config';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _workingDirectoryController = TextEditingController();
  final TextEditingController _executableTargetPathController = TextEditingController();
  final TextEditingController _executableArgumentsController = TextEditingController();
  final TextEditingController _scriptPathController = TextEditingController();
  final TextEditingController _scriptInterpreterPathController = TextEditingController();
  final TextEditingController _jarPathController = TextEditingController();
  final TextEditingController _javaExecutablePathController = TextEditingController();
  final TextEditingController _smtpProfileIdController = TextEditingController();
  final TextEditingController _emailFromController = TextEditingController();
  final TextEditingController _emailToController = TextEditingController();
  final TextEditingController _emailCcController = TextEditingController();
  final TextEditingController _emailBccController = TextEditingController();
  final TextEditingController _emailSubjectController = TextEditingController();
  final TextEditingController _emailBodyController = TextEditingController();
  final TextEditingController _emailAttachmentsController = TextEditingController();
  final TextEditingController _comProgIdController = TextEditingController();
  final TextEditingController _comMemberNameController = TextEditingController();
  final TextEditingController _comArgumentsController = TextEditingController(text: '{}');
  final TextEditingController _executorPathController = TextEditingController();
  final TextEditingController _projectPathController = TextEditingController();
  final TextEditingController _data7ConfigPathController = TextEditingController();
  final TextEditingController _connectionIdController = TextEditingController();
  final TextEditingController _connectionLabelController = TextEditingController();
  final TextEditingController _developerConnectionSearchController = TextEditingController();
  String _developerConnectionSearchQuery = '';
  final TextEditingController _maxRuntimeMinutesController = TextEditingController();
  final TextEditingController _allowedProfilesController = TextEditingController();
  final TextEditingController _allowedEnvironmentVariableNamesController = TextEditingController();
  final TextEditingController _environmentVariablesController = TextEditingController();
  final TextEditingController _acceptedExitCodesController = TextEditingController();
  final TextEditingController _runtimeParameterSchemaController = TextEditingController();
  final TextEditingController _maxConcurrentController = TextEditingController(text: '1');
  final TextEditingController _maxQueuedController = TextEditingController(text: '100');
  final TextEditingController _allowedWorkingDirectoriesController = TextEditingController();
  final TextEditingController _allowedContextDirectoriesController = TextEditingController();

  String? _editingActionId;
  AgentActionType _draftType = AgentActionType.commandLine;
  AgentActionState _state = AgentActionState.needsValidation;
  bool _notifyOnSuccess = false;
  bool _notifyOnFailure = false;
  bool _notifyOnTimeout = false;
  int _maxAttempts = 1;
  bool _allowRemoteRetry = false;
  int _maxRuntimeMinutes = 30;
  bool _killMainProcessOnTimeout = true;
  AgentActionOnAppExitBehavior _onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
  AgentActionProcessWindowMode _processWindowMode = AgentActionProcessWindowMode.normal;
  AgentActionOutputEncodingMode _stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  AgentActionOutputEncodingMode _stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  bool _captureStdout = true;
  bool _captureStderr = true;
  bool _redactBeforePersisting = true;
  AgentActionConcurrencyBehavior _concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
  bool _remoteEnabled = false;
  bool _remoteAdHoc = false;
  bool _remoteApprovalGranted = false;
  bool _runElevated = false;
  AgentActionPathChangePolicy _pathChangePolicy = AgentActionPathChangePolicy.failIfChanged;
  AgentActionContextInjectionMode _contextInjectionMode = AgentActionContextInjectionMode.argument;
  String? _validationMessage;

  static const AgentOperationalProfileResolver _operationalProfileResolver = AgentOperationalProfileResolver();
  static const ActionEnvironmentResolver _environmentResolver = ActionEnvironmentResolver();
  static const String _localRemoteApprover = 'local-ui';

  @override
  void initState() {
    super.initState();
    _loadDefinition(widget.definition);
  }

  @override
  void didUpdateWidget(_AgentActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition?.id != widget.definition?.id || oldWidget.definition?.type != widget.definition?.type) {
      _loadDefinition(widget.definition);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _commandController.dispose();
    _workingDirectoryController.dispose();
    _executableTargetPathController.dispose();
    _executableArgumentsController.dispose();
    _scriptPathController.dispose();
    _scriptInterpreterPathController.dispose();
    _jarPathController.dispose();
    _javaExecutablePathController.dispose();
    _smtpProfileIdController.dispose();
    _emailFromController.dispose();
    _emailToController.dispose();
    _emailCcController.dispose();
    _emailBccController.dispose();
    _emailSubjectController.dispose();
    _emailBodyController.dispose();
    _emailAttachmentsController.dispose();
    _comProgIdController.dispose();
    _comMemberNameController.dispose();
    _comArgumentsController.dispose();
    _executorPathController.dispose();
    _projectPathController.dispose();
    _data7ConfigPathController.dispose();
    _connectionIdController.dispose();
    _connectionLabelController.dispose();
    _developerConnectionSearchController.dispose();
    _maxRuntimeMinutesController.dispose();
    _allowedProfilesController.dispose();
    _allowedEnvironmentVariableNamesController.dispose();
    _environmentVariablesController.dispose();
    _acceptedExitCodesController.dispose();
    _runtimeParameterSchemaController.dispose();
    _maxConcurrentController.dispose();
    _maxQueuedController.dispose();
    _allowedWorkingDirectoriesController.dispose();
    _allowedContextDirectoriesController.dispose();
    super.dispose();
  }

  void _loadDefinition(AgentActionDefinition? definition) {
    _validationMessage = null;
    if (definition == null) {
      _clearDraft();
      return;
    }
    _editingActionId = definition.id;
    _nameController.text = definition.name;
    _descriptionController.text = definition.description ?? '';
    _state = definition.state;
    final notification = definition.policies.notification;
    _notifyOnSuccess = notification.notifyOnSuccess;
    _notifyOnFailure = notification.notifyOnFailure;
    _notifyOnTimeout = notification.notifyOnTimeout;
    final retry = definition.policies.retry;
    _maxAttempts = retry.maxAttempts < 1 ? 1 : retry.maxAttempts;
    _allowRemoteRetry = retry.allowRemote;
    final timeout = definition.policies.timeout;
    _maxRuntimeMinutes = timeout.maxRuntime.inMinutes < 1 ? 1 : timeout.maxRuntime.inMinutes;
    _maxRuntimeMinutesController.text = '$_maxRuntimeMinutes';
    _killMainProcessOnTimeout = timeout.killMainProcessOnTimeout;
    final environment = definition.policies.environment;
    _allowedProfilesController.text = environment.allowedProfiles.join(', ');
    _allowedEnvironmentVariableNamesController.text = environment.allowedVariableNames.join(', ');
    _environmentVariablesController.text = _formatEnvironmentVariables(environment.variables);
    final exitCode = definition.policies.exitCode;
    _acceptedExitCodesController.text = exitCode.acceptedExitCodes.join(', ');
    _onAppExit = definition.policies.lifecycle.onAppExit;
    _processWindowMode = definition.policies.process.windowMode;
    final encoding = definition.policies.encoding;
    _stdoutEncodingMode = encoding.stdout;
    _stderrEncodingMode = encoding.stderr;
    final capture = definition.policies.capture;
    _captureStdout = capture.captureStdout;
    _captureStderr = capture.captureStderr;
    _redactBeforePersisting = capture.redactBeforePersisting;
    final queue = definition.policies.queue;
    _maxConcurrentController.text = '${queue.maxConcurrent}';
    _maxQueuedController.text = '${queue.maxQueued}';
    _concurrencyBehavior = queue.concurrencyBehavior;
    final pathPolicy = definition.policies.path;
    _allowedWorkingDirectoriesController.text = pathPolicy.allowedWorkingDirectories.join(', ');
    _allowedContextDirectoriesController.text = pathPolicy.allowedContextDirectories.join(', ');
    final remote = definition.policies.remote;
    _remoteEnabled = remote.isEnabled;
    _remoteAdHoc = remote.allowAdHoc && widget.provider.isRemoteAdHocAgentActionsEnabled;
    _remoteApprovalGranted = remote.approvedAt != null && !remote.requiresReapproval;
    _runElevated = definition.policies.elevated.runElevated && widget.provider.isElevatedAgentActionsEnabled;
    final contextPolicy = definition.policies.context;
    _contextInjectionMode = contextPolicy.injectionMode;
    final runtimeSchema = contextPolicy.runtimeParameterSchema;
    _runtimeParameterSchemaController.text = runtimeSchema == null
        ? ''
        : const JsonEncoder.withIndent('  ').convert(runtimeSchema);
    switch (definition.config) {
      case final CommandLineActionConfig config:
        _draftType = AgentActionType.commandLine;
        _commandController.text = config.command;
        _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
        _pathChangePolicy = config.workingDirectory?.pathChangePolicy ?? AgentActionPathChangePolicy.failIfChanged;
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.clear();
        _comMemberNameController.clear();
        _comArgumentsController.text = '{}';
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final ExecutableActionConfig config:
        _draftType = AgentActionType.executable;
        _commandController.clear();
        _executableTargetPathController.text = config.executablePath.originalPath;
        _executableArgumentsController.text = config.arguments.join('\n');
        _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.clear();
        _comMemberNameController.clear();
        _comArgumentsController.text = '{}';
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final ScriptActionConfig config:
        _draftType = AgentActionType.script;
        _commandController.clear();
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.text = config.scriptPath.originalPath;
        _scriptInterpreterPathController.text = config.interpreterPath?.originalPath ?? '';
        _executableArgumentsController.text = config.arguments.join('\n');
        _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.clear();
        _comMemberNameController.clear();
        _comArgumentsController.text = '{}';
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final JarActionConfig config:
        _draftType = AgentActionType.jar;
        _commandController.clear();
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.text = config.jarPath.originalPath;
        _javaExecutablePathController.text = config.javaExecutablePath?.originalPath ?? '';
        _executableArgumentsController.text = config.arguments.join('\n');
        _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.clear();
        _comMemberNameController.clear();
        _comArgumentsController.text = '{}';
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final EmailActionConfig config:
        _draftType = AgentActionType.email;
        _commandController.clear();
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _workingDirectoryController.clear();
        _smtpProfileIdController.text = config.smtpProfileId;
        _emailFromController.text = config.from;
        _emailToController.text = config.to.join('\n');
        _emailCcController.text = config.cc.join('\n');
        _emailBccController.text = config.bcc.join('\n');
        _emailSubjectController.text = config.subjectTemplate;
        _emailBodyController.text = config.bodyTemplate;
        _emailAttachmentsController.text = config.attachmentPaths.map((path) => path.originalPath).join('\n');
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final ComObjectActionConfig config:
        _draftType = AgentActionType.comObject;
        _commandController.clear();
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _workingDirectoryController.clear();
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.text = config.progId;
        _comMemberNameController.text = config.memberName;
        _comArgumentsController.text = const JsonEncoder.withIndent('  ').convert(config.arguments);
        _executorPathController.clear();
        _projectPathController.clear();
        _data7ConfigPathController.clear();
        _connectionIdController.clear();
        _connectionLabelController.clear();
        widget.provider.clearDeveloperData7Connections(notify: false);
      case final DeveloperActionConfig config:
        _draftType = AgentActionType.developer;
        _commandController.clear();
        _executableTargetPathController.clear();
        _executableArgumentsController.clear();
        _scriptPathController.clear();
        _scriptInterpreterPathController.clear();
        _jarPathController.clear();
        _javaExecutablePathController.clear();
        _workingDirectoryController.clear();
        _smtpProfileIdController.clear();
        _emailFromController.clear();
        _emailToController.clear();
        _emailCcController.clear();
        _emailBccController.clear();
        _emailSubjectController.clear();
        _emailBodyController.clear();
        _emailAttachmentsController.clear();
        _comProgIdController.clear();
        _comMemberNameController.clear();
        _comArgumentsController.text = '{}';
        _executorPathController.text = config.executorPath.originalPath;
        _projectPathController.text = config.projectPath.originalPath;
        _data7ConfigPathController.text = config.data7ConfigPath.originalPath;
        _connectionIdController.text = config.connectionId;
        _connectionLabelController.text = config.connectionLabel;
        _scheduleDeveloperConnectionReload(
          pathPolicy: definition.policies.path,
          selectedConnectionId: config.connectionId,
        );
    }
  }

  void _clearDraft([AgentActionType? draftType]) {
    _editingActionId = null;
    _draftType = draftType ?? _draftType;
    _nameController.clear();
    _descriptionController.clear();
    _commandController.clear();
    _workingDirectoryController.clear();
    _executableTargetPathController.clear();
    _executableArgumentsController.clear();
    _scriptPathController.clear();
    _scriptInterpreterPathController.clear();
    _jarPathController.clear();
    _javaExecutablePathController.clear();
    _smtpProfileIdController.clear();
    _emailFromController.clear();
    _emailToController.clear();
    _emailCcController.clear();
    _emailBccController.clear();
    _emailSubjectController.clear();
    _emailBodyController.clear();
    _emailAttachmentsController.clear();
    _comProgIdController.clear();
    _comMemberNameController.clear();
    _comArgumentsController.text = '{}';
    _executorPathController.clear();
    _projectPathController.clear();
    _data7ConfigPathController.clear();
    _connectionIdController.clear();
    _connectionLabelController.clear();
    _state = AgentActionState.needsValidation;
    _notifyOnSuccess = false;
    _notifyOnFailure = false;
    _notifyOnTimeout = false;
    _maxAttempts = 1;
    _allowRemoteRetry = false;
    _maxRuntimeMinutes = 30;
    _maxRuntimeMinutesController.text = '30';
    _killMainProcessOnTimeout = true;
    _allowedProfilesController.clear();
    _allowedEnvironmentVariableNamesController.clear();
    _environmentVariablesController.clear();
    _acceptedExitCodesController.text = '0';
    _onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
    _processWindowMode = AgentActionProcessWindowMode.normal;
    _stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    _stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    _captureStdout = true;
    _captureStderr = true;
    _redactBeforePersisting = true;
    _maxConcurrentController.text = '1';
    _maxQueuedController.text = '100';
    _concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
    _allowedWorkingDirectoriesController.clear();
    _allowedContextDirectoriesController.clear();
    _remoteEnabled = false;
    _remoteAdHoc = false;
    _remoteApprovalGranted = false;
    _runElevated = false;
    _validationMessage = null;
    widget.provider.clearDeveloperData7Connections(notify: false);
  }

  AgentActionRetryPolicy _draftRetryPolicy() {
    return AgentActionRetryPolicy(
      maxAttempts: _maxAttempts,
      allowRemote: _allowRemoteRetry,
    );
  }

  AgentActionTimeoutPolicy _draftTimeoutPolicy() {
    return AgentActionTimeoutPolicy(
      maxRuntime: Duration(minutes: _maxRuntimeMinutes),
      killMainProcessOnTimeout: _killMainProcessOnTimeout,
    );
  }

  AgentActionNotificationPolicy _draftNotificationPolicy() {
    return AgentActionNotificationPolicy(
      notifyOnSuccess: _notifyOnSuccess,
      notifyOnFailure: _notifyOnFailure,
      notifyOnTimeout: _notifyOnTimeout,
    );
  }

  AgentActionEnvironmentPolicy _draftEnvironmentPolicy() {
    return AgentActionEnvironmentPolicy(
      allowedProfiles: _parseAllowedProfiles(_allowedProfilesController.text),
      allowedVariableNames: _parseCommaSeparatedTokens(_allowedEnvironmentVariableNamesController.text),
      variables: _parseEnvironmentVariables(_environmentVariablesController.text),
    );
  }

  AgentActionExitCodePolicy _draftExitCodePolicy(Set<int> acceptedExitCodes) {
    return AgentActionExitCodePolicy(acceptedExitCodes: acceptedExitCodes);
  }

  AgentActionLifecyclePolicy _draftLifecyclePolicy() {
    return AgentActionLifecyclePolicy(onAppExit: _onAppExit);
  }

  AgentActionProcessPolicy _draftProcessPolicy() {
    return AgentActionProcessPolicy(windowMode: _processWindowMode);
  }

  AgentActionEncodingPolicy _draftEncodingPolicy() {
    return AgentActionEncodingPolicy(
      stdout: _stdoutEncodingMode,
      stderr: _stderrEncodingMode,
    );
  }

  AgentActionCapturePolicy _draftCapturePolicy() {
    return AgentActionCapturePolicy(
      captureStdout: _captureStdout,
      captureStderr: _captureStderr,
      redactBeforePersisting: _redactBeforePersisting,
    );
  }

  AgentActionQueuePolicy _draftQueuePolicy() {
    return AgentActionQueuePolicy(
      maxConcurrent: _parsePositiveInt(_maxConcurrentController.text) ?? 1,
      maxQueued: _parsePositiveInt(_maxQueuedController.text) ?? 100,
      concurrencyBehavior: _concurrencyBehavior,
    );
  }

  AgentActionPathPolicy _draftPathPolicy() {
    return AgentActionPathPolicy(
      allowedWorkingDirectories: _parseCommaSeparatedTokens(_allowedWorkingDirectoriesController.text),
      allowedContextDirectories: _parseCommaSeparatedTokens(_allowedContextDirectoriesController.text),
    );
  }

  int? _parsePositiveInt(String input) {
    final parsed = int.tryParse(input.trim());
    if (parsed == null || parsed < 1) {
      return null;
    }

    return parsed;
  }

  bool get _draftCapturesProcessOutput {
    return switch (_draftType) {
      AgentActionType.commandLine ||
      AgentActionType.executable ||
      AgentActionType.script ||
      AgentActionType.jar ||
      AgentActionType.developer => true,
      AgentActionType.email || AgentActionType.comObject => false,
    };
  }

  AgentActionElevatedPolicy _draftElevatedPolicy() {
    if (!widget.provider.isElevatedAgentActionsEnabled) {
      return const AgentActionElevatedPolicy();
    }
    return AgentActionElevatedPolicy(runElevated: _runElevated);
  }

  AgentActionContextPolicy _draftContextPolicy() {
    final schemaText = _runtimeParameterSchemaController.text.trim();
    if (schemaText.isEmpty) {
      return AgentActionContextPolicy(
        injectionMode: _contextInjectionMode,
      );
    }

    final decoded = jsonDecode(schemaText);
    if (decoded is! Map) {
      throw const FormatException('Runtime parameter schema must be a JSON object.');
    }

    return AgentActionContextPolicy(
      injectionMode: _contextInjectionMode,
      runtimeParameterSchema: decoded.cast<String, Object?>(),
    );
  }

  bool _validateDraftContextPolicy() {
    try {
      _draftContextPolicy();
      return true;
    } on FormatException {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormRuntimeParameterSchemaHint;
      });
      return false;
    }
  }

  bool _validateDraftEnvironmentPolicy() {
    try {
      final policy = _draftEnvironmentPolicy();
      final failure = _environmentResolver.validatePolicy(
        actionId: _editingActionId ?? 'draft',
        policy: policy,
      );
      if (failure != null) {
        setState(() {
          _validationMessage = failure.context['user_message'] as String? ?? failure.message;
        });
        return false;
      }
      return true;
    } on FormatException {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormEnvironmentVariablesInvalid;
      });
      return false;
    }
  }

  bool _validateDraftQueuePolicy() {
    if (_parsePositiveInt(_maxConcurrentController.text) == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidQueueLimits;
      });
      return false;
    }

    if (_parsePositiveInt(_maxQueuedController.text) == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidQueueLimits;
      });
      return false;
    }

    return true;
  }

  bool _validateDraftPolicies() {
    return _validateDraftContextPolicy() && _validateDraftEnvironmentPolicy() && _validateDraftQueuePolicy();
  }

  AgentActionRemotePolicy _draftRemotePolicy() {
    if (!_remoteEnabled) {
      return const AgentActionRemotePolicy();
    }

    final existing = widget.definition;
    final previous = existing?.policies.remote;
    final DateTime? approvedAt;
    if (!_remoteApprovalGranted) {
      approvedAt = null;
    } else if (previous?.approvedAt == null || (previous?.requiresReapproval ?? false)) {
      approvedAt = DateTime.now().toUtc();
    } else {
      approvedAt = previous!.approvedAt;
    }

    return AgentActionRemotePolicy(
      isEnabled: true,
      allowAdHoc: widget.provider.isRemoteAdHocAgentActionsEnabled && _remoteAdHoc,
      approvedBy: approvedAt == null ? null : (previous?.approvedBy ?? _localRemoteApprover),
      approvedAt: approvedAt,
      approvalReason: previous?.approvalReason,
      riskFingerprint: previous?.riskFingerprint,
      requiresReapproval: !_remoteApprovalGranted && (previous?.requiresReapproval ?? false),
    );
  }

  Set<String> _parseAllowedProfiles(String input) => _parseCommaSeparatedTokens(input);

  Set<String> _parseCommaSeparatedTokens(String input) {
    if (input.trim().isEmpty) {
      return const <String>{};
    }

    return input.split(',').map((String part) => part.trim()).where((String part) => part.isNotEmpty).toSet();
  }

  Map<String, String> _parseEnvironmentVariables(String input) {
    final variables = <String, String>{};
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        throw const FormatException('Invalid environment variable line.');
      }

      final name = line.substring(0, separatorIndex).trim();
      if (name.isEmpty) {
        throw const FormatException('Environment variable name is blank.');
      }

      variables[name] = line.substring(separatorIndex + 1);
    }

    return Map<String, String>.unmodifiable(variables);
  }

  String _formatEnvironmentVariables(Map<String, String> variables) {
    if (variables.isEmpty) {
      return '';
    }

    final names = variables.keys.toList()..sort();
    return names.map((String name) => '$name=${variables[name]}').join('\n');
  }

  Set<int>? _tryParseAcceptedExitCodes(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const <int>{0};
    }

    final codes = <int>{};
    for (final part in trimmed.split(',')) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final code = int.tryParse(token);
      if (code == null) {
        return null;
      }
      codes.add(code);
    }

    if (codes.isEmpty) {
      return const <int>{0};
    }

    return codes;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormName);
      });
      return;
    }

    final acceptedExitCodes = _tryParseAcceptedExitCodes(_acceptedExitCodesController.text);
    if (acceptedExitCodes == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidExitCodes;
      });
      return;
    }

    if (_remoteEnabled && !_remoteApprovalGranted) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormRemoteApprovalRequired;
      });
      return;
    }

    final saveResult = switch (_draftType) {
      AgentActionType.commandLine => _saveCommandLineDraft(),
      AgentActionType.executable => _saveExecutableDraft(),
      AgentActionType.script => _saveScriptDraft(),
      AgentActionType.jar => _saveJarDraft(),
      AgentActionType.email => _saveEmailDraft(),
      AgentActionType.comObject => _saveComObjectDraft(),
      AgentActionType.developer => _saveDeveloperDraft(),
    };
    if (!saveResult) {
      return;
    }

    setState(() {
      _validationMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.provider.isSaving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                _editingActionId == null ? _createTitle() : _editTitle(),
                style: context.sectionTitle,
              ),
            ),
            Button(
              onPressed: saving
                  ? null
                  : () {
                      setState(_clearDraft);
                    },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.add),
                  const SizedBox(width: AppSpacing.xs),
                  Text(widget.l10n.agentActionsFormNew),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_validationMessage != null) ...[
          InfoBar(
            title: Text(widget.l10n.agentActionsValidationTitle),
            content: Text(_validationMessage!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final nameField = AppTextField(
              label: widget.l10n.agentActionsFormName,
              controller: _nameController,
              enabled: !saving && widget.provider.canSaveAction,
              textInputAction: TextInputAction.next,
            );
            final typeField = AppDropdown<AgentActionType>(
              label: widget.l10n.agentActionsFormType,
              value: _draftType,
              items: _editableDraftTypes
                  .map(
                    (type) {
                      final unavailable = widget.provider.isActionTypeUnavailable(type);
                      return ComboBoxItem<AgentActionType>(
                        value: type,
                        enabled: !unavailable,
                        child: Text(
                          unavailable
                              ? '${_typeLabel(type, widget.l10n)} (${widget.l10n.agentActionsRiskRunnerUnavailable})'
                              : _typeLabel(type, widget.l10n),
                        ),
                      );
                    },
                  )
                  .toList(growable: false),
              onChanged: saving || _editingActionId != null
                  ? null
                  : (value) {
                      if (value == null || value == _draftType) {
                        return;
                      }
                      setState(() {
                        _clearDraft(value);
                      });
                    },
            );
            final stateField = AppDropdown<AgentActionState>(
              label: widget.l10n.agentActionsFormState,
              value: _state,
              items: AgentActionState.values
                  .map(
                    (state) => ComboBoxItem<AgentActionState>(
                      value: state,
                      child: Text(_stateLabel(state, widget.l10n)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _state = value;
                      });
                    },
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nameField,
                  const SizedBox(height: AppSpacing.sm),
                  typeField,
                  const SizedBox(height: AppSpacing.sm),
                  stateField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: nameField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 220, child: typeField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 220, child: stateField),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormDescription,
          controller: _descriptionController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._buildDraftFields(saving),
        const SizedBox(height: AppSpacing.md),
        _buildExecutionPoliciesSection(saving),
        const SizedBox(height: AppSpacing.md),
        _buildRuntimePoliciesSection(saving),
        const SizedBox(height: AppSpacing.md),
        _buildRemotePolicySection(saving),
        const SizedBox(height: AppSpacing.md),
        _buildNotificationPolicySection(saving),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: saving || !widget.provider.canSaveAction
                ? null
                : () {
                    unawaited(_save());
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (saving)
                  const SizedBox.square(
                    dimension: 14,
                    child: ProgressRing(strokeWidth: 2),
                  )
                else
                  const Icon(FluentIcons.save),
                const SizedBox(width: AppSpacing.xs),
                Text(widget.l10n.agentActionsFormSave),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExecutionPoliciesSection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormExecutionPoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormExecutionPoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: AppDropdown<int>(
                label: widget.l10n.agentActionsFormMaxAttempts,
                value: _maxAttempts,
                items: List<ComboBoxItem<int>>.generate(
                  5,
                  (int index) {
                    final attempts = index + 1;
                    return ComboBoxItem<int>(
                      value: attempts,
                      child: Text('$attempts'),
                    );
                  },
                  growable: false,
                ),
                onChanged: enabled
                    ? (int? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _maxAttempts = value;
                        });
                      }
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormMaxRuntimeMinutes,
                controller: _maxRuntimeMinutesController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: (String value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null && parsed > 0) {
                    setState(() {
                      _maxRuntimeMinutes = parsed;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _killMainProcessOnTimeout,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _killMainProcessOnTimeout = value ?? true;
                      });
                    }
                  : null,
              content: Text(widget.l10n.agentActionsFormKillOnTimeout),
            ),
            Checkbox(
              checked: _allowRemoteRetry,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _allowRemoteRetry = value ?? false;
                      });
                    }
                  : null,
              content: Text(widget.l10n.agentActionsFormAllowRemoteRetry),
            ),
            if (widget.provider.isElevatedAgentActionsEnabled)
              Checkbox(
                checked: _runElevated,
                onChanged:
                    enabled && widget.provider.isElevatedRunnerConfigured && !widget.provider.isElevatedRunnerDegraded
                    ? (bool? value) {
                        unawaited(_onRunElevatedChanged(value ?? false));
                      }
                    : null,
                content: Text(widget.l10n.agentActionsFormRunElevated),
              ),
          ],
        ),
        if (widget.provider.isElevatedAgentActionsEnabled) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.l10n.agentActionsFormRunElevatedHint,
            style: context.bodyMuted,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppDropdown<AgentActionContextInjectionMode>(
          label: widget.l10n.agentActionsFormContextInjectionMode,
          value: _contextInjectionMode,
          items: [
            ComboBoxItem(
              value: AgentActionContextInjectionMode.argument,
              child: Text(widget.l10n.agentActionsFormContextInjectionArgument),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.file,
              child: Text(widget.l10n.agentActionsFormContextInjectionFile),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.environment,
              child: Text(widget.l10n.agentActionsFormContextInjectionEnvironment),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.stdin,
              child: Text(widget.l10n.agentActionsFormContextInjectionStdin),
            ),
          ],
          onChanged: enabled
              ? (AgentActionContextInjectionMode? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _contextInjectionMode = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionPathChangePolicy>(
          label: widget.l10n.agentActionsFormPathChangePolicy,
          value: _pathChangePolicy,
          items: [
            ComboBoxItem(
              value: AgentActionPathChangePolicy.failIfChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyFail),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.warnIfChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyWarn),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.allowChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyAllow),
            ),
          ],
          onChanged: enabled
              ? (AgentActionPathChangePolicy? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _pathChangePolicy = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormRuntimeParameterSchema,
          controller: _runtimeParameterSchemaController,
          enabled: enabled,
          maxLines: 6,
          hint: widget.l10n.agentActionsFormRuntimeParameterSchemaHint,
        ),
      ],
    );
  }

  Widget _buildRuntimePoliciesSection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    final currentProfile = _operationalProfileResolver.currentProfile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormRuntimePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormRuntimePoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          title: Text(
            currentProfile == null
                ? widget.l10n.agentActionsFormCurrentOperationalProfileUnset
                : widget.l10n.agentActionsFormCurrentOperationalProfile(currentProfile),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedProfiles,
          controller: _allowedProfilesController,
          enabled: enabled,
          hint: widget.l10n.agentActionsFormAllowedProfilesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedEnvironmentVariableNames,
          controller: _allowedEnvironmentVariableNamesController,
          enabled: enabled,
          hint: widget.l10n.agentActionsFormAllowedEnvironmentVariableNamesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEnvironmentVariables,
          controller: _environmentVariablesController,
          enabled: enabled,
          maxLines: 6,
          hint: widget.l10n.agentActionsFormEnvironmentVariablesHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.l10n.agentActionsFormQueuePolicyDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final maxConcurrentField = AppTextField(
              label: widget.l10n.agentActionsFormMaxConcurrent,
              controller: _maxConcurrentController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );
            final maxQueuedField = AppTextField(
              label: widget.l10n.agentActionsFormMaxQueued,
              controller: _maxQueuedController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  maxConcurrentField,
                  const SizedBox(height: AppSpacing.sm),
                  maxQueuedField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: maxConcurrentField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: maxQueuedField),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionConcurrencyBehavior>(
          label: widget.l10n.agentActionsFormConcurrencyBehavior,
          value: _concurrencyBehavior,
          items: AgentActionConcurrencyBehavior.values
              .map(
                (AgentActionConcurrencyBehavior behavior) => ComboBoxItem<AgentActionConcurrencyBehavior>(
                  value: behavior,
                  child: Text(_concurrencyBehaviorLabel(behavior, widget.l10n)),
                ),
              )
              .toList(growable: false),
          onChanged: enabled
              ? (AgentActionConcurrencyBehavior? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _concurrencyBehavior = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.l10n.agentActionsFormPathAllowlistDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedWorkingDirectories,
          controller: _allowedWorkingDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: widget.l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedContextDirectories,
          controller: _allowedContextDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: widget.l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_draftCapturesProcessOutput) ...[
          AppDropdown<AgentActionProcessWindowMode>(
            label: widget.l10n.agentActionsFormProcessWindowMode,
            value: _processWindowMode,
            items: AgentActionProcessWindowMode.values
                .map(
                  (AgentActionProcessWindowMode mode) => ComboBoxItem<AgentActionProcessWindowMode>(
                    value: mode,
                    child: Text(_processWindowModeLabel(mode, widget.l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: enabled
                ? (AgentActionProcessWindowMode? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _processWindowMode = value;
                    });
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.l10n.agentActionsFormCapturePolicyDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Checkbox(
                checked: _captureStdout,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _captureStdout = value ?? true;
                        });
                      }
                    : null,
                content: Text(widget.l10n.agentActionsFormCaptureStdout),
              ),
              Checkbox(
                checked: _captureStderr,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _captureStderr = value ?? true;
                        });
                      }
                    : null,
                content: Text(widget.l10n.agentActionsFormCaptureStderr),
              ),
              Checkbox(
                checked: _redactBeforePersisting,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _redactBeforePersisting = value ?? true;
                        });
                      }
                    : null,
                content: Text(widget.l10n.agentActionsFormRedactBeforePersisting),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.l10n.agentActionsFormOutputEncodingDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: widget.l10n.agentActionsFormStdoutEncoding,
                  value: _stdoutEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(_outputEncodingModeLabel(mode, widget.l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _stdoutEncodingMode = value;
                          });
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: widget.l10n.agentActionsFormStderrEncoding,
                  value: _stderrEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(_outputEncodingModeLabel(mode, widget.l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _stderrEncodingMode = value;
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final exitCodesField = AppTextField(
              label: widget.l10n.agentActionsFormAcceptedExitCodes,
              controller: _acceptedExitCodesController,
              enabled: enabled,
              hint: widget.l10n.agentActionsFormAcceptedExitCodesHint,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
            );
            final onAppExitField = AppDropdown<AgentActionOnAppExitBehavior>(
              label: widget.l10n.agentActionsFormOnAppExit,
              value: _onAppExit,
              items: AgentActionOnAppExitBehavior.values
                  .map(
                    (AgentActionOnAppExitBehavior behavior) => ComboBoxItem<AgentActionOnAppExitBehavior>(
                      value: behavior,
                      child: Text(_onAppExitLabel(behavior, widget.l10n)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (AgentActionOnAppExitBehavior? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _onAppExit = value;
                      });
                    }
                  : null,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  exitCodesField,
                  const SizedBox(height: AppSpacing.sm),
                  onAppExitField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: exitCodesField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 280, child: onAppExitField),
              ],
            );
          },
        ),
      ],
    );
  }

  String _onAppExitLabel(AgentActionOnAppExitBehavior behavior, AppLocalizations l10n) {
    return switch (behavior) {
      AgentActionOnAppExitBehavior.killMainProcess => l10n.agentActionsFormOnAppExitKill,
      AgentActionOnAppExitBehavior.waitThenKillMainProcess => l10n.agentActionsFormOnAppExitWaitThenKill,
      AgentActionOnAppExitBehavior.leaveRunning => l10n.agentActionsFormOnAppExitLeaveRunning,
    };
  }

  String _processWindowModeLabel(AgentActionProcessWindowMode mode, AppLocalizations l10n) {
    return switch (mode) {
      AgentActionProcessWindowMode.normal => l10n.agentActionsFormProcessWindowModeNormal,
      AgentActionProcessWindowMode.hidden => l10n.agentActionsFormProcessWindowModeHidden,
      AgentActionProcessWindowMode.minimized => l10n.agentActionsFormProcessWindowModeMinimized,
    };
  }

  String _concurrencyBehaviorLabel(AgentActionConcurrencyBehavior behavior, AppLocalizations l10n) {
    return switch (behavior) {
      AgentActionConcurrencyBehavior.allowParallel => l10n.agentActionsFormConcurrencyAllowParallel,
      AgentActionConcurrencyBehavior.enqueue => l10n.agentActionsFormConcurrencyEnqueue,
      AgentActionConcurrencyBehavior.reject => l10n.agentActionsFormConcurrencyReject,
      AgentActionConcurrencyBehavior.ignore => l10n.agentActionsFormConcurrencyIgnore,
    };
  }

  String _outputEncodingModeLabel(AgentActionOutputEncodingMode mode, AppLocalizations l10n) {
    return switch (mode) {
      AgentActionOutputEncodingMode.utf8 => l10n.agentActionsFormOutputEncodingUtf8,
      AgentActionOutputEncodingMode.systemConsole => l10n.agentActionsFormOutputEncodingSystemConsole,
    };
  }

  Widget _buildRemotePolicySection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    final remoteFeatureEnabled = widget.provider.isRemoteAgentActionsEnabled;
    final remoteAdHocFeatureEnabled = widget.provider.isRemoteAdHocAgentActionsEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormRemotePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormRemotePoliciesDescription,
          style: context.bodyMuted,
        ),
        if (!remoteFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsFormRemoteFeatureDisabledTitle),
            content: Text(widget.l10n.agentActionsFormRemoteFeatureDisabledMessage),
            isLong: true,
          ),
        ] else if (!remoteAdHocFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsFormRemoteAdHocFeatureDisabledTitle),
            content: Text(widget.l10n.agentActionsFormRemoteAdHocFeatureDisabledMessage),
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _remoteEnabled,
              onChanged: !enabled
                  ? null
                  : (bool? value) {
                      unawaited(_onRemoteEnabledChanged(value ?? false));
                    },
              content: Text(widget.l10n.agentActionsFormRemoteExecutionEnabled),
            ),
            Checkbox(
              checked: _remoteAdHoc,
              onChanged: !enabled || !_remoteEnabled || !remoteAdHocFeatureEnabled
                  ? null
                  : (bool? value) {
                      unawaited(_onRemoteAdHocChanged(value ?? false));
                    },
              content: Text(widget.l10n.agentActionsFormRemoteAdHocEnabled),
            ),
          ],
        ),
        if (widget.definition?.policies.remote.requiresReapproval ?? false) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            key: _AgentActionsPageKeys.remoteReapprovalInfoBar,
            title: Text(widget.l10n.agentActionsFormRemoteReapprovalRequiredTitle),
            content: Text(widget.l10n.agentActionsFormRemoteReapprovalRequiredMessage),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ] else if (_remoteEnabled && _remoteApprovalGranted) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.l10n.agentActionsFormRemoteApprovedHint,
            style: context.bodyMuted,
          ),
        ],
      ],
    );
  }

  Future<void> _onRemoteEnabledChanged(bool enabled) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      final needsReapproval = widget.definition?.policies.remote.requiresReapproval ?? false;
      var confirmed = false;
      if (context.mounted) {
        confirmed = needsReapproval
            ? await confirmReapproveRemoteAgentAction(
                context: context,
                l10n: widget.l10n,
              )
            : await confirmEnableRemoteAgentAction(
                context: context,
                l10n: widget.l10n,
              );
      }
      if (!confirmed || !context.mounted) {
        return;
      }

      setState(() {
        _remoteEnabled = true;
        _remoteApprovalGranted = true;
      });
      return;
    }

    setState(() {
      _remoteEnabled = false;
      _remoteAdHoc = false;
      _remoteApprovalGranted = false;
    });
  }

  Future<void> _onRemoteAdHocChanged(bool enabled) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      var confirmed = false;
      if (context.mounted) {
        confirmed = await confirmEnableRemoteAdHocAgentAction(
          context: context,
          l10n: widget.l10n,
        );
      }
      if (!confirmed || !context.mounted) {
        return;
      }
    }

    setState(() {
      _remoteAdHoc = enabled;
    });
  }

  Future<void> _onRunElevatedChanged(bool enabled) async {
    if (!enabled) {
      setState(() {
        _runElevated = false;
      });
      return;
    }

    if (!context.mounted) {
      return;
    }

    final confirmed = await confirmEnableElevatedAgentAction(
      context: context,
      l10n: widget.l10n,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    setState(() {
      _runElevated = true;
    });
  }

  Widget _buildNotificationPolicySection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormNotificationsTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormNotificationsDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _notifyOnSuccess,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnSuccess = value ?? false;
                      });
                    }
                  : null,
              content: Text(widget.l10n.agentActionsFormNotifyOnSuccess),
            ),
            Checkbox(
              checked: _notifyOnFailure,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnFailure = value ?? false;
                      });
                    }
                  : null,
              content: Text(widget.l10n.agentActionsFormNotifyOnFailure),
            ),
            Checkbox(
              checked: _notifyOnTimeout,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnTimeout = value ?? false;
                      });
                    }
                  : null,
              content: Text(widget.l10n.agentActionsFormNotifyOnTimeout),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildDraftFields(bool saving) {
    return switch (_draftType) {
      AgentActionType.commandLine => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormCommand,
          controller: _commandController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 2,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.executable => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormExecutablePath,
          controller: _executableTargetPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickExecutableTargetPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.comObject => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormComProgId,
          controller: _comProgIdController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormComMemberName,
          controller: _comMemberNameController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormComArguments,
          controller: _comArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 8,
          textInputAction: TextInputAction.done,
          hint: widget.l10n.agentActionsFormComArgumentsHint,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.email => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormSmtpProfileId,
          controller: _smtpProfileIdController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormSmtpProfileIdHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailFrom,
          controller: _emailFromController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailTo,
          controller: _emailToController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailToHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailCc,
          controller: _emailCcController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailCcHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailBcc,
          controller: _emailBccController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailBccHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailSubject,
          controller: _emailSubjectController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailSubjectHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailBody,
          controller: _emailBodyController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 8,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailBodyHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailAttachments,
          controller: _emailAttachmentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          hint: widget.l10n.agentActionsFormEmailAttachmentsHint,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.jar => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormJarPath,
          controller: _jarPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseJarPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickJarPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormJavaExecutablePath,
          controller: _javaExecutablePathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormJavaExecutablePathHint,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseJavaExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickJavaExecutablePath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.script => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormScriptPath,
          controller: _scriptPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseScriptPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickScriptPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormInterpreterPath,
          controller: _scriptInterpreterPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormInterpreterPathHint,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseInterpreterPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickScriptInterpreterPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.developer => <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormExecutorPath,
                controller: _executorPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperBinaryPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseExecutorPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperExecutorPath,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormProjectPath,
                controller: _projectPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperBinaryPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseProjectPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperProjectPath,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _DeveloperPathShortcuts(
          primaryLabel: widget.l10n.agentActionsFormUseDefaultExecutorPath,
          onPrimaryPressed: saving || !widget.provider.canSaveAction ? null : _applyDefaultDeveloperExecutorPath,
        ),
        ..._buildDeveloperBinaryPathHints(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Button(
              onPressed: saving || !widget.provider.canSaveAction || widget.provider.isLoadingDeveloperConnections
                  ? null
                  : () {
                      unawaited(
                        _reloadDeveloperConnections(
                          pathPolicy: _draftPathPolicy(),
                        ),
                      );
                    },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.provider.isLoadingDeveloperConnections)
                    const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.refresh),
                  const SizedBox(width: AppSpacing.xs),
                  Text(widget.l10n.agentActionsFormReloadConnections),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (widget.provider.usedDefaultDeveloperData7ConfigPath)
              Expanded(
                child: Text(
                  widget.l10n.agentActionsFormDefaultConfigResolved,
                  style: context.bodyMuted,
                ),
              ),
          ],
        ),
        if (widget.provider.developerConnectionLookupMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsValidationTitle),
            content: Text(widget.provider.developerConnectionLookupMessage!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        ..._buildDeveloperConnectionStatus(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormData7ConfigPath,
                controller: _data7ConfigPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperConfigPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseData7ConfigPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperData7ConfigPath,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormConnectionId,
                controller: _connectionIdController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperConnectionIdChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _DeveloperPathShortcuts(
          primaryLabel: widget.l10n.agentActionsFormUseDefaultConfigBinPath,
          onPrimaryPressed: saving || !widget.provider.canSaveAction ? null : _applyDefaultDeveloperData7ConfigBinPath,
          secondaryLabel: widget.l10n.agentActionsFormUseDefaultConfigRootPath,
          onSecondaryPressed: saving || !widget.provider.canSaveAction
              ? null
              : _applyDefaultDeveloperData7ConfigRootPath,
        ),
        ..._buildDeveloperConfigPathHints(),
        ..._buildDeveloperResolvedConfigHints(),
        if (widget.provider.developerConnections.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: widget.l10n.agentActionsFormConnectionSearch,
            controller: _developerConnectionSearchController,
            enabled: !saving && widget.provider.canSaveAction,
            onChanged: (value) {
              setState(() {
                _developerConnectionSearchQuery = value;
              });
            },
            textInputAction: TextInputAction.search,
          ),
          if (_developerConnectionFilterHasNoMatches) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.l10n.agentActionsFormConnectionFilterEmpty,
              style: context.bodyMuted,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<String>(
          label: widget.l10n.agentActionsFormConnectionSelector,
          value:
              _developerConnectionsForSelector().any(
                (option) => option.id == _connectionIdController.text.trim(),
              )
              ? _connectionIdController.text.trim()
              : null,
          items: _developerConnectionsForSelector()
              .map(
                (option) => ComboBoxItem<String>(
                  value: option.id,
                  child: Text(option.label),
                ),
              )
              .toList(growable: false),
          onChanged: saving || !widget.provider.canSaveAction ? null : _applyDeveloperConnectionSelection,
          placeholder: Text(widget.l10n.agentActionsFormConnectionSelectorPlaceholder),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormConnectionLabel,
          controller: _connectionLabelController,
          enabled: false,
          readOnly: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
    };
  }

  List<Widget> _buildDeveloperBinaryPathHints() {
    final hints = <_DeveloperHintData>[];
    final executorPath = _executorPathController.text.trim();
    if (executorPath.isNotEmpty) {
      final normalizedExecutorPath = _normalizePathForComparison(executorPath);
      if (!_endsWithFileName(normalizedExecutorPath, 'executor.exe')) {
        hints.add(
          _DeveloperHintData.warning(
            widget.l10n.agentActionsFormExecutorPathHintExpectedFileName,
          ),
        );
      } else if (normalizedExecutorPath == _normalizePathForComparison(_defaultDeveloperExecutorPath)) {
        hints.add(
          _DeveloperHintData.info(
            widget.l10n.agentActionsFormExecutorPathHintDefault,
          ),
        );
      }
      hints.addAll(
        _buildDeveloperFileInspectionHints(
          path: executorPath,
          missingMessage: widget.l10n.agentActionsFormExecutorPathHintMissing,
          directoryMessage: widget.l10n.agentActionsFormExecutorPathHintDirectory,
        ),
      );
    }

    final projectPath = _projectPathController.text.trim();
    if (projectPath.isNotEmpty) {
      if (!_normalizePathForComparison(projectPath).endsWith('.7proj')) {
        hints.add(
          _DeveloperHintData.warning(
            widget.l10n.agentActionsFormProjectPathHintExpectedExtension,
          ),
        );
      }
      hints.addAll(
        _buildDeveloperFileInspectionHints(
          path: projectPath,
          missingMessage: widget.l10n.agentActionsFormProjectPathHintMissing,
          directoryMessage: widget.l10n.agentActionsFormProjectPathHintDirectory,
        ),
      );
    }

    if (hints.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(hints: hints),
    ];
  }

  List<Widget> _buildDeveloperConfigPathHints() {
    final configPath = _data7ConfigPathController.text.trim();
    if (configPath.isEmpty) {
      return const <Widget>[];
    }

    final normalizedConfigPath = _normalizePathForComparison(configPath);
    final hints = <_DeveloperHintData>[];
    if (!_endsWithFileName(normalizedConfigPath, 'data7.config')) {
      hints.add(
        _DeveloperHintData.warning(
          widget.l10n.agentActionsFormData7ConfigPathHintExpectedFileName,
        ),
      );
    } else if (normalizedConfigPath == _normalizePathForComparison(_defaultDeveloperConfigBinPath)) {
      hints.add(
        _DeveloperHintData.info(
          widget.l10n.agentActionsFormData7ConfigPathHintDefaultBin,
        ),
      );
    } else if (normalizedConfigPath == _normalizePathForComparison(_defaultDeveloperConfigRootPath)) {
      hints.add(
        _DeveloperHintData.info(
          widget.l10n.agentActionsFormData7ConfigPathHintDefaultRoot,
        ),
      );
    }
    hints.addAll(
      _buildDeveloperFileInspectionHints(
        path: configPath,
        missingMessage: widget.l10n.agentActionsFormData7ConfigPathHintMissing,
        directoryMessage: widget.l10n.agentActionsFormData7ConfigPathHintDirectory,
      ),
    );

    if (hints.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(hints: hints),
    ];
  }

  List<Widget> _buildDeveloperResolvedConfigHints() {
    final resolvedPath = widget.provider.resolvedDeveloperData7ConfigPath?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return const <Widget>[];
    }

    final typedPath = _data7ConfigPathController.text.trim();
    final normalizedResolvedPath = _normalizePathForComparison(resolvedPath);
    final normalizedTypedPath = _normalizePathForComparison(typedPath);
    final message = normalizedTypedPath.isNotEmpty && normalizedResolvedPath != normalizedTypedPath
        ? widget.l10n.agentActionsFormLoadedConfigPath(resolvedPath)
        : widget.l10n.agentActionsFormResolvedConfigPath(resolvedPath);

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(
        hints: <_DeveloperHintData>[
          _DeveloperHintData.info(message),
        ],
      ),
    ];
  }

  List<Widget> _buildDeveloperConnectionStatus() {
    final definition = widget.definition;
    if (definition == null || definition.config is! DeveloperActionConfig) {
      return const <Widget>[];
    }
    if (_draftType != AgentActionType.developer) {
      return const <Widget>[];
    }
    if (widget.provider.developerConnectionLookupMessage != null) {
      return const <Widget>[];
    }

    final config = definition.config as DeveloperActionConfig;
    final selectedConnectionId = _connectionIdController.text.trim();
    if (selectedConnectionId.isEmpty) {
      return const <Widget>[];
    }

    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == selectedConnectionId)
        .firstOrNull;

    if (selectedOption == null && widget.provider.developerConnections.isNotEmpty) {
      final savedConnectionId = config.connectionId.trim();
      final isSavedConnectionMissing = selectedConnectionId == savedConnectionId;
      return <Widget>[
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          key: isSavedConnectionMissing
              ? _AgentActionsPageKeys.developerConnectionMissingInfoBar
              : _AgentActionsPageKeys.developerConnectionUnknownInfoBar,
          title: Text(
            isSavedConnectionMissing
                ? widget.l10n.agentActionsFormConnectionMissingTitle
                : widget.l10n.agentActionsFormConnectionUnknownTitle,
          ),
          content: Text(
            isSavedConnectionMissing
                ? widget.l10n.agentActionsFormConnectionMissingMessage
                : widget.l10n.agentActionsFormConnectionUnknownMessage,
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ];
    }

    final savedSnapshotHash = config.connectionSnapshotHash?.trim();
    if (selectedOption != null &&
        savedSnapshotHash != null &&
        savedSnapshotHash.isNotEmpty &&
        savedSnapshotHash != selectedOption.snapshotHash) {
      return <Widget>[
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          key: _AgentActionsPageKeys.developerConnectionChangedInfoBar,
          title: Text(widget.l10n.agentActionsFormConnectionChangedTitle),
          content: Text(widget.l10n.agentActionsFormConnectionChangedMessage),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ];
    }

    return const <Widget>[];
  }

  bool _saveExecutableDraft() {
    final executablePath = _executableTargetPathController.text.trim();
    if (executablePath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutablePath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveExecutableAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        executablePath: executablePath,
        arguments: _parseStructuredArguments(_executableArgumentsController.text),
        workingDirectory: _workingDirectoryController.text,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        encodingPolicy: _draftEncodingPolicy(),
        capturePolicy: _draftCapturePolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  bool _saveJarDraft() {
    final jarPath = _jarPathController.text.trim();
    if (jarPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormJarPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveJarAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        jarPath: jarPath,
        javaExecutablePath: _javaExecutablePathController.text,
        arguments: _parseStructuredArguments(_executableArgumentsController.text),
        workingDirectory: _workingDirectoryController.text,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        encodingPolicy: _draftEncodingPolicy(),
        capturePolicy: _draftCapturePolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  bool _saveEmailDraft() {
    final smtpProfileId = _smtpProfileIdController.text.trim();
    if (smtpProfileId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormSmtpProfileId);
      });
      return false;
    }

    final from = _emailFromController.text.trim();
    if (from.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailFrom);
      });
      return false;
    }

    final to = _parseStructuredArguments(_emailToController.text);
    if (to.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailTo);
      });
      return false;
    }

    final subject = _emailSubjectController.text.trim();
    if (subject.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailSubject);
      });
      return false;
    }

    final body = _emailBodyController.text.trim();
    if (body.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailBody);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    final attachmentPaths = _parseStructuredArguments(_emailAttachmentsController.text)
        .map(
          (path) => AgentActionPathReference(
            originalPath: path,
            pathChangePolicy: _pathChangePolicy,
          ),
        )
        .toList(growable: false);

    unawaited(
      widget.provider.saveEmailAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        smtpProfileId: smtpProfileId,
        from: from,
        to: to,
        cc: _parseStructuredArguments(_emailCcController.text),
        bcc: _parseStructuredArguments(_emailBccController.text),
        subjectTemplate: subject,
        bodyTemplate: body,
        attachmentPaths: attachmentPaths,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  bool _saveComObjectDraft() {
    final progId = _comProgIdController.text.trim();
    if (progId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComProgId);
      });
      return false;
    }

    final memberName = _comMemberNameController.text.trim();
    if (memberName.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComMemberName);
      });
      return false;
    }

    final argumentsResult = _parseComObjectArguments(_comArgumentsController.text);
    if (argumentsResult == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidComArguments;
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveComObjectAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        progId: progId,
        memberName: memberName,
        arguments: argumentsResult,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  Map<String, Object?>? _parseComObjectArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }

      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  bool _saveScriptDraft() {
    final scriptPath = _scriptPathController.text.trim();
    if (scriptPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormScriptPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveScriptAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        scriptPath: scriptPath,
        interpreterPath: _scriptInterpreterPathController.text,
        arguments: _parseStructuredArguments(_executableArgumentsController.text),
        workingDirectory: _workingDirectoryController.text,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        encodingPolicy: _draftEncodingPolicy(),
        capturePolicy: _draftCapturePolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  List<String> _parseStructuredArguments(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
  }

  bool _saveCommandLineDraft() {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormCommand);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveCommandLineAction(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        command: command,
        workingDirectory: _workingDirectoryController.text,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        encodingPolicy: _draftEncodingPolicy(),
        capturePolicy: _draftCapturePolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  bool _saveDeveloperDraft() {
    final executorPath = _executorPathController.text.trim();
    if (executorPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutorPath);
      });
      return false;
    }

    final projectPath = _projectPathController.text.trim();
    if (projectPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormProjectPath);
      });
      return false;
    }

    final connectionId = _connectionIdController.text.trim();
    if (connectionId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormConnectionId);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    unawaited(
      widget.provider.saveDeveloperData7Action(
        actionId: _editingActionId,
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        executorPath: executorPath,
        projectPath: projectPath,
        data7ConfigPath: _data7ConfigPathController.text,
        connectionId: connectionId,
        connectionLabel: _connectionLabelController.text,
        state: _state,
        notificationPolicy: _draftNotificationPolicy(),
        retryPolicy: _draftRetryPolicy(),
        timeoutPolicy: _draftTimeoutPolicy(),
        environmentPolicy: _draftEnvironmentPolicy(),
        exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
        processPolicy: _draftProcessPolicy(),
        encodingPolicy: _draftEncodingPolicy(),
        capturePolicy: _draftCapturePolicy(),
        lifecyclePolicy: _draftLifecyclePolicy(),
        remotePolicy: _draftRemotePolicy(),
        elevatedPolicy: _draftElevatedPolicy(),
        contextPolicy: _draftContextPolicy(),
        pathChangePolicy: _pathChangePolicy,
        queuePolicy: _draftQueuePolicy(),
        pathPolicy: _draftPathPolicy(),
      ),
    );
    return true;
  }

  String _createTitle() {
    return switch (_draftType) {
      AgentActionType.commandLine => widget.l10n.agentActionsFormCreateTitle,
      AgentActionType.executable => widget.l10n.agentActionsFormCreateExecutableTitle,
      AgentActionType.script => widget.l10n.agentActionsFormCreateScriptTitle,
      AgentActionType.jar => widget.l10n.agentActionsFormCreateJarTitle,
      AgentActionType.email => widget.l10n.agentActionsFormCreateEmailTitle,
      AgentActionType.comObject => widget.l10n.agentActionsFormCreateComObjectTitle,
      AgentActionType.developer => widget.l10n.agentActionsFormCreateDeveloperTitle,
    };
  }

  String _editTitle() {
    return switch (_draftType) {
      AgentActionType.commandLine => widget.l10n.agentActionsFormEditTitle,
      AgentActionType.executable => widget.l10n.agentActionsFormEditExecutableTitle,
      AgentActionType.script => widget.l10n.agentActionsFormEditScriptTitle,
      AgentActionType.jar => widget.l10n.agentActionsFormEditJarTitle,
      AgentActionType.email => widget.l10n.agentActionsFormEditEmailTitle,
      AgentActionType.comObject => widget.l10n.agentActionsFormEditComObjectTitle,
      AgentActionType.developer => widget.l10n.agentActionsFormEditDeveloperTitle,
    };
  }

  void _scheduleDeveloperConnectionReload({
    required AgentActionPathPolicy pathPolicy,
    required String? selectedConnectionId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _draftType != AgentActionType.developer) {
        return;
      }
      unawaited(
        _reloadDeveloperConnections(
          pathPolicy: pathPolicy,
          selectedConnectionId: selectedConnectionId,
        ),
      );
    });
  }

  Future<void> _reloadDeveloperConnections({
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String? selectedConnectionId,
  }) async {
    final actionId = (_editingActionId?.trim().isNotEmpty ?? false) ? _editingActionId!.trim() : 'developer-draft';
    await widget.provider.loadDeveloperData7Connections(
      actionId: actionId,
      data7ConfigPath: _data7ConfigPathController.text,
      selectedConnectionId: selectedConnectionId ?? _connectionIdController.text,
      pathPolicy: pathPolicy,
    );

    if (!mounted) {
      return;
    }

    final resolvedPath = widget.provider.resolvedDeveloperData7ConfigPath;
    final typedConfigPath = _data7ConfigPathController.text.trim();
    if (resolvedPath != null &&
        resolvedPath.isNotEmpty &&
        (typedConfigPath.isEmpty || widget.provider.usedDefaultDeveloperData7ConfigPath)) {
      _data7ConfigPathController.text = resolvedPath;
    }

    final selectedId = selectedConnectionId ?? _connectionIdController.text.trim();
    final selectedOption = widget.provider.developerConnections.where((option) => option.id == selectedId).firstOrNull;
    if (selectedOption != null) {
      _applyDeveloperConnectionSelection(selectedOption.id);
      return;
    }

    if (selectedId.isEmpty && widget.provider.developerConnections.length == 1) {
      _applyDeveloperConnectionSelection(widget.provider.developerConnections.single.id);
    }
  }

  void _applyDeveloperConnectionSelection(String? connectionId) {
    if (connectionId == null || connectionId.trim().isEmpty) {
      return;
    }

    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == connectionId)
        .firstOrNull;
    if (selectedOption == null) {
      return;
    }

    setState(() {
      _connectionIdController.text = selectedOption.id;
      _connectionLabelController.text = selectedOption.label;
    });
  }

  void _handleDeveloperConfigPathChanged(String _) {
    widget.provider.clearDeveloperData7Connections(notify: false);
    setState(() {
      _connectionLabelController.clear();
      _developerConnectionSearchQuery = '';
      _developerConnectionSearchController.clear();
      _validationMessage = null;
    });
  }

  bool get _developerConnectionFilterHasNoMatches {
    final query = _developerConnectionSearchQuery.trim();
    if (query.isEmpty || widget.provider.developerConnections.isEmpty) {
      return false;
    }

    final needle = query.toLowerCase();
    return !widget.provider.developerConnections.any(
      (option) => option.id.toLowerCase().contains(needle) || option.label.toLowerCase().contains(needle),
    );
  }

  List<DeveloperData7ConnectionOption> _developerConnectionsForSelector() {
    final all = widget.provider.developerConnections;
    final query = _developerConnectionSearchQuery.trim().toLowerCase();
    final matched = query.isEmpty
        ? all
        : all
              .where(
                (option) => option.id.toLowerCase().contains(query) || option.label.toLowerCase().contains(query),
              )
              .toList(growable: false);

    final selectedId = _connectionIdController.text.trim();
    if (selectedId.isEmpty || matched.any((option) => option.id == selectedId)) {
      return matched;
    }

    final selected = all.where((option) => option.id == selectedId).firstOrNull;
    if (selected == null) {
      return matched;
    }

    return <DeveloperData7ConnectionOption>[selected, ...matched];
  }

  void _handleDeveloperBinaryPathChanged(String _) {
    setState(() {
      _validationMessage = null;
    });
  }

  void _handleDeveloperConnectionIdChanged(String value) {
    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == value.trim())
        .firstOrNull;
    setState(() {
      _connectionLabelController.text = selectedOption?.label ?? '';
    });
  }

  Future<void> _pickJarPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseJarPath,
      allowedExtensions: const ['jar'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _jarPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickJavaExecutablePath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseJavaExecutablePath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _javaExecutablePathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickScriptPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseScriptPath,
      allowedExtensions: const ['ps1', 'bat', 'cmd', 'py'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _scriptPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickScriptInterpreterPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseInterpreterPath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _scriptInterpreterPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickExecutableTargetPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseExecutablePath,
      allowedExtensions: const ['exe', 'bat', 'cmd'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _executableTargetPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperExecutorPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseExecutorPath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _executorPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  void _applyDefaultDeveloperExecutorPath() {
    setState(() {
      _executorPathController.text = _defaultDeveloperExecutorPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperProjectPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseProjectPath,
      allowedExtensions: const ['7proj'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _projectPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperData7ConfigPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseData7ConfigPath,
      allowedExtensions: const ['config'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _data7ConfigPathController.text = selectedPath;
      _connectionIdController.clear();
      _connectionLabelController.clear();
      _validationMessage = null;
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await _reloadDeveloperConnections(
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<void> _applyDefaultDeveloperData7ConfigBinPath() async {
    await _applyDeveloperData7ConfigPath(_defaultDeveloperConfigBinPath);
  }

  Future<void> _applyDefaultDeveloperData7ConfigRootPath() async {
    await _applyDeveloperData7ConfigPath(_defaultDeveloperConfigRootPath);
  }

  Future<void> _applyDeveloperData7ConfigPath(String path) async {
    setState(() {
      _data7ConfigPathController.text = path;
      _connectionIdController.clear();
      _connectionLabelController.clear();
      _validationMessage = null;
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await _reloadDeveloperConnections(
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<String?> _pickSingleFile({
    required String dialogTitle,
    required List<String> allowedExtensions,
  }) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );
      return picked?.files.singleOrNull?.path;
    } on Exception {
      if (!mounted) {
        return null;
      }

      setState(() {
        _validationMessage = widget.l10n.agentActionsFormBrowseFileError;
      });
      return null;
    }
  }

  String _normalizePathForComparison(String path) {
    return path.trim().replaceAll('/', r'\').toLowerCase();
  }

  bool _endsWithFileName(String normalizedPath, String fileName) {
    final expectedSuffix = r'\' + fileName.toLowerCase();
    return normalizedPath.endsWith(expectedSuffix) || normalizedPath == fileName.toLowerCase();
  }

  List<_DeveloperHintData> _buildDeveloperFileInspectionHints({
    required String path,
    required String missingMessage,
    required String directoryMessage,
  }) {
    try {
      final entityType = FileSystemEntity.typeSync(path);
      return switch (entityType) {
        FileSystemEntityType.notFound => <_DeveloperHintData>[
          _DeveloperHintData.warning(missingMessage),
        ],
        FileSystemEntityType.directory => <_DeveloperHintData>[
          _DeveloperHintData.warning(directoryMessage),
        ],
        _ => const <_DeveloperHintData>[],
      };
    } on FileSystemException {
      return <_DeveloperHintData>[
        _DeveloperHintData.warning(
          widget.l10n.agentActionsFormPathHintInspectionFailed,
        ),
      ];
    }
  }
}

class _PathPickerButton extends StatelessWidget {
  const _PathPickerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 14),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _DeveloperPathShortcuts extends StatelessWidget {
  const _DeveloperPathShortcuts({
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        Button(
          onPressed: onPrimaryPressed,
          child: Text(primaryLabel),
        ),
        if (secondaryLabel != null)
          Button(
            onPressed: onSecondaryPressed,
            child: Text(secondaryLabel!),
          ),
      ],
    );
  }
}

class _DeveloperHintsWrap extends StatelessWidget {
  const _DeveloperHintsWrap({
    required this.hints,
  });

  final List<_DeveloperHintData> hints;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: hints
          .map(
            (hint) => _DeveloperHintChip(hint: hint),
          )
          .toList(growable: false),
    );
  }
}

class _DeveloperHintChip extends StatelessWidget {
  const _DeveloperHintChip({
    required this.hint,
  });

  final _DeveloperHintData hint;

  @override
  Widget build(BuildContext context) {
    final color = hint.isWarning ? AppColors.warning : FluentTheme.of(context).resources.textFillColorSecondary;
    final icon = hint.isWarning ? FluentIcons.warning : FluentIcons.info;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            hint.message,
            style: context.captionText.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _DeveloperHintData {
  const _DeveloperHintData._({
    required this.message,
    required this.isWarning,
  });

  const _DeveloperHintData.info(String message) : this._(message: message, isWarning: false);

  const _DeveloperHintData.warning(String message) : this._(message: message, isWarning: true);

  final String message;
  final bool isWarning;
}

class _AgentActionTestPreview extends StatelessWidget {
  const _AgentActionTestPreview({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final commandPreview = provider.lastTestCommandPreview;
    final previewError = provider.lastTestPreviewErrorMessage;
    final diagnostics = provider.lastTestDiagnostics;
    if ((commandPreview == null || commandPreview.isEmpty) &&
        (previewError == null || previewError.isEmpty) &&
        diagnostics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: _AgentActionsPageKeys.testPreview,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsTestPreviewTitle, style: context.captionText),
          if (commandPreview != null && commandPreview.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _OutputBlock(
              label: l10n.agentActionsTestPreviewCommandLabel,
              value: commandPreview,
              truncated: false,
              l10n: l10n,
            ),
          ],
          if (previewError != null && previewError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            InfoBar(
              title: Text(l10n.agentActionsTestPreviewUnavailableTitle),
              content: Text(previewError),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          if (diagnostics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: diagnostics.entries
                  .where((entry) => entry.key != 'path_snapshot_warnings')
                  .map(
                    (entry) => _DiagnosticLine(
                      label: _testDiagnosticLabel(entry.key, l10n),
                      value: _testDiagnosticValue(entry.key, entry.value, l10n),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (diagnostics['path_snapshot_warnings'] is List) ...[
            const SizedBox(height: AppSpacing.xs),
            _OutputBlock(
              label: l10n.agentActionsTestPreviewPathSnapshotWarnings,
              value: (diagnostics['path_snapshot_warnings']! as List)
                  .map(
                    (warning) =>
                        warning is Map ? warning['message']?.toString() ?? warning.toString() : warning.toString(),
                  )
                  .join('\n'),
              truncated: false,
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionRow extends StatelessWidget {
  const _ExecutionRow({
    required this.execution,
    required this.provider,
    required this.l10n,
  });

  final AgentActionExecution execution;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final failureMessage = execution.failureMessage;
    final isAuditHighlight =
        provider.auditCorrelationExecutionId != null && provider.auditCorrelationExecutionId == execution.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Container(
        decoration: isAuditHighlight
            ? BoxDecoration(
                border: Border.all(
                  color: FluentTheme.of(context).accentColor,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        padding: isAuditHighlight ? const EdgeInsets.all(AppSpacing.xs) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon(execution.status), size: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_statusLabel(execution.status, l10n)),
                      const SizedBox(height: 2),
                      Text(
                        _executionSubtitle(execution, l10n),
                        style: context.captionText,
                      ),
                      if (execution.failurePhase != null &&
                          execution.failurePhase!.trim().isNotEmpty &&
                          !execution.status.isSuccess) ...[
                        const SizedBox(height: 2),
                        Text(
                          l10n.agentActionsExecutionFailurePhaseLabel(
                            _localizedFailurePhase(execution.failurePhase!, l10n),
                          ),
                          style: context.captionText,
                        ),
                      ],
                      if (failureMessage != null && failureMessage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        SelectableText(failureMessage, style: context.captionText),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Tooltip(
                  message: l10n.agentActionsCancelExecution,
                  child: Semantics(
                    button: true,
                    label: l10n.agentActionsCancelExecution,
                    child: IconButton(
                      icon: provider.hasCancellationInProgress(execution.id)
                          ? const SizedBox.square(
                              dimension: 14,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : const Icon(FluentIcons.cancel),
                      onPressed: provider.canCancelExecution(execution)
                          ? () {
                              unawaited(provider.cancelExecution(execution));
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _ExecutionDiagnostics(
              key: ValueKey<String>('execution-diagnostics-${execution.id}'),
              execution: execution,
              l10n: l10n,
              onSliceCapturedOutput: provider.sliceCapturedOutput,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionDiagnostics extends StatefulWidget {
  const _ExecutionDiagnostics({
    required this.execution,
    required this.l10n,
    required this.onSliceCapturedOutput,
    super.key,
  });

  static const AgentActionFailureDiagnosticsResolver _diagnosticsResolver = AgentActionFailureDiagnosticsResolver();

  final AgentActionExecution execution;
  final AppLocalizations l10n;
  final Future<Result<CapturedOutputUtf8Window>> Function({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    int? maxBytes,
  })
  onSliceCapturedOutput;

  @override
  State<_ExecutionDiagnostics> createState() => _ExecutionDiagnosticsState();
}

class _ExecutionDiagnosticsState extends State<_ExecutionDiagnostics> {
  static const AgentActionExecutionSupportExport _supportExport = AgentActionExecutionSupportExport();

  Future<void> _copySupportExport(BuildContext context) async {
    final text = _supportExport.buildJson(widget.execution);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(widget.l10n.agentActionsDiagnosticsCopiedToast),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final execution = widget.execution;
    final l10n = widget.l10n;
    final stdoutText = execution.stdoutText;
    final stderrText = execution.stderrText;
    final showStdout = execution.stdoutStoredInChunks || (stdoutText != null && stdoutText.isNotEmpty);
    final showStderr = execution.stderrStoredInChunks || (stderrText != null && stderrText.isNotEmpty);
    final duration = _executionDuration(execution);
    final diagnostics = _ExecutionDiagnostics._diagnosticsResolver.resolve(execution);
    final correctiveAction = _correctiveActionLabel(
      diagnostics.correctiveAction,
      l10n,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.agentActionsDiagnosticsTitle, style: context.captionText),
              ),
              Button(
                key: _AgentActionsPageKeys.executionSupportCopyButton(execution.id),
                onPressed: () {
                  unawaited(_copySupportExport(context));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.copy, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l10n.agentActionsDiagnosticsCopySupport),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _DiagnosticLine(
                label: l10n.agentActionsDiagnosticsExecutionId,
                value: execution.id,
              ),
              _DiagnosticLine(
                label: l10n.agentActionsDiagnosticsSource,
                value: _sourceLabel(execution.source, l10n),
              ),
              if (execution.queueStartedAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsQueueStartedAt,
                  value: execution.queueStartedAt!.toLocal().toString(),
                ),
              if (execution.idempotencyKey != null && execution.idempotencyKey!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsIdempotencyKey,
                  value: execution.idempotencyKey!.trim(),
                ),
              if (execution.requestedBy != null && execution.requestedBy!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRequestedBy,
                  value: execution.requestedBy!.trim(),
                ),
              if (execution.traceId != null && execution.traceId!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTraceId,
                  value: execution.traceId!.trim(),
                ),
              if (execution.runtimeInstanceId != null && execution.runtimeInstanceId!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRuntimeInstanceId,
                  value: execution.runtimeInstanceId!.trim(),
                ),
              if (execution.runtimeSessionId != null && execution.runtimeSessionId!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRuntimeSessionId,
                  value: execution.runtimeSessionId!.trim(),
                ),
              if (execution.triggerId != null && execution.triggerId!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggerId,
                  value: execution.triggerId!.trim(),
                ),
              if (execution.triggerType != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggerType,
                  value: _triggerTypeLabel(execution.triggerType!, l10n),
                ),
              if (execution.scheduledAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsScheduledAt,
                  value: execution.scheduledAt!.toLocal().toString(),
                ),
              if (execution.triggeredAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggeredAt,
                  value: execution.triggeredAt!.toLocal().toString(),
                ),
              if (execution.pid != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsPid,
                  value: execution.pid.toString(),
                ),
              if (execution.processStartedAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsStartedAt,
                  value: execution.processStartedAt!.toLocal().toString(),
                ),
              if (execution.finishedAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFinishedAt,
                  value: execution.finishedAt!.toLocal().toString(),
                ),
              if (execution.timeoutAt != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTimeoutAt,
                  value: execution.timeoutAt!.toLocal().toString(),
                ),
              if (duration != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsDuration,
                  value: duration,
                ),
              if (execution.processExecutable != null && execution.processExecutable!.isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsExecutable,
                  value: execution.processExecutable!,
                ),
              if (execution.processArgumentCount != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsArgumentCount,
                  value: execution.processArgumentCount.toString(),
                ),
              if (execution.processCommandPreview != null && execution.processCommandPreview!.isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsCommandPreview,
                  value: execution.processCommandPreview!,
                ),
              if (execution.definitionSnapshotHash != null && execution.definitionSnapshotHash!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsDefinitionSnapshotHash,
                  value: execution.definitionSnapshotHash!.trim(),
                ),
              if (execution.contextHash != null && execution.contextHash!.trim().isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsContextHash,
                  value: execution.contextHash!.trim(),
                ),
              if (execution.redactionApplied)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRedactionApplied,
                  value: l10n.agentActionsDiagnosticsValueYes,
                ),
              if (execution.failureCode != null && execution.failureCode!.isNotEmpty)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFailureCode,
                  value: execution.failureCode!,
                ),
              if (diagnostics.failurePhase != null)
                _DiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFailurePhase,
                  value: _localizedFailurePhase(diagnostics.failurePhase!, l10n),
                ),
            ],
          ),
          if (correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _OutputBlock(
              label: l10n.agentActionsDiagnosticsCorrectiveAction,
              value: correctiveAction,
              truncated: false,
              l10n: l10n,
            ),
          ],
          if (showStdout) ...[
            const SizedBox(height: AppSpacing.xs),
            _PagedCapturedOutput(
              label: l10n.agentActionsDiagnosticsStdout,
              loadMoreLabel: l10n.agentActionsDiagnosticsLoadMoreStdout,
              fullText: stdoutText,
              storedInChunks: execution.stdoutStoredInChunks,
              storageTruncated: execution.stdoutTruncated,
              l10n: l10n,
              onSlice: execution.stdoutStoredInChunks
                  ? (int offsetUtf8, int maxBytes) => widget.onSliceCapturedOutput(
                      executionId: execution.id,
                      stream: AgentActionCapturedOutputConstants.stdoutStream,
                      offsetUtf8: offsetUtf8,
                      maxBytes: maxBytes,
                    )
                  : null,
            ),
          ],
          if (showStderr) ...[
            const SizedBox(height: AppSpacing.xs),
            _PagedCapturedOutput(
              label: l10n.agentActionsDiagnosticsStderr,
              loadMoreLabel: l10n.agentActionsDiagnosticsLoadMoreStderr,
              fullText: stderrText,
              storedInChunks: execution.stderrStoredInChunks,
              storageTruncated: execution.stderrTruncated,
              l10n: l10n,
              onSlice: execution.stderrStoredInChunks
                  ? (int offsetUtf8, int maxBytes) => widget.onSliceCapturedOutput(
                      executionId: execution.id,
                      stream: AgentActionCapturedOutputConstants.stderrStream,
                      offsetUtf8: offsetUtf8,
                      maxBytes: maxBytes,
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _PagedCapturedOutput extends StatefulWidget {
  const _PagedCapturedOutput({
    required this.label,
    required this.loadMoreLabel,
    required this.storageTruncated,
    required this.l10n,
    this.fullText,
    this.storedInChunks = false,
    this.onSlice,
  }) : assert(
         fullText != null || onSlice != null,
         'Either fullText or onSlice must be provided for output display',
       );

  final String label;
  final String loadMoreLabel;
  final String? fullText;
  final bool storedInChunks;
  final bool storageTruncated;
  final AppLocalizations l10n;
  final Future<Result<CapturedOutputUtf8Window>> Function(int, int)? onSlice;

  @override
  State<_PagedCapturedOutput> createState() => _PagedCapturedOutputState();
}

class _PagedCapturedOutputState extends State<_PagedCapturedOutput> {
  static const int _pageBytes = AgentActionRpcConstants.defaultMaxOutputBytesPerStream;

  var _visibleText = '';
  var _nextUtf8Offset = 0;
  var _hasMore = false;
  var _isLoading = false;
  var _isLoadingMore = false;
  String? _loadError;

  void _assignFromWindow(CapturedOutputUtf8Window window, {required bool append}) {
    _visibleText = append ? '$_visibleText${window.text}' : window.text;
    _nextUtf8Offset = window.nextOffset;
    _hasMore = window.responseTruncated;
    _loadError = null;
  }

  Future<void> _loadSlice({required int offsetUtf8, required bool append}) async {
    final onSlice = widget.onSlice;
    if (onSlice == null) {
      return;
    }

    setState(() {
      if (append) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
      }
      _loadError = null;
    });

    final result = await onSlice(offsetUtf8, _pageBytes);
    if (!mounted) {
      return;
    }

    result.fold(
      (CapturedOutputUtf8Window window) {
        setState(() {
          _assignFromWindow(window, append: append);
          _isLoading = false;
          _isLoadingMore = false;
        });
      },
      (Exception failure) {
        setState(() {
          _loadError = failure is domain_errors.Failure
              ? failure.message
              : widget.l10n.agentActionsDiagnosticsOutputLoadFailed;
          _isLoading = false;
          _isLoadingMore = false;
        });
      },
    );
  }

  void _loadInitialWindow() {
    final fullText = widget.fullText;
    if (fullText != null) {
      _assignFromWindow(
        sliceUtf8TextWindow(fullText, 0, _pageBytes),
        append: false,
      );
      return;
    }

    unawaited(_loadSlice(offsetUtf8: 0, append: false));
  }

  @override
  void initState() {
    super.initState();
    _loadInitialWindow();
  }

  @override
  void didUpdateWidget(covariant _PagedCapturedOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullText != widget.fullText ||
        oldWidget.storedInChunks != widget.storedInChunks ||
        oldWidget.onSlice != widget.onSlice) {
      setState(() {
        _visibleText = '';
        _nextUtf8Offset = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
        _loadError = null;
      });
      _loadInitialWindow();
    }
  }

  void _loadMore() {
    final fullText = widget.fullText;
    if (fullText != null) {
      setState(() {
        _assignFromWindow(
          sliceUtf8TextWindow(fullText, _nextUtf8Offset, _pageBytes),
          append: true,
        );
      });
      return;
    }

    unawaited(_loadSlice(offsetUtf8: _nextUtf8Offset, append: true));
  }

  @override
  Widget build(BuildContext context) {
    final suffixes = <String>[
      if (widget.storedInChunks) widget.l10n.agentActionsDiagnosticsStoredInChunks,
      if (widget.storageTruncated) widget.l10n.agentActionsDiagnosticsTruncated,
    ];
    final title = suffixes.isEmpty ? widget.label : '${widget.label} (${suffixes.join(', ')})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.captionText),
        const SizedBox(height: 2),
        if (_loadError != null)
          InfoBar(
            title: Text(widget.l10n.agentActionsDiagnosticsOutputLoadFailed),
            content: Text(_loadError!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          )
        else if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: SizedBox.square(
              dimension: 20,
              child: ProgressRing(strokeWidth: 2),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).resources.controlFillColorDefault,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              _visibleText,
              style: context.captionText,
            ),
          ),
        if (_hasMore && !_isLoading && _loadError == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: HyperlinkButton(
              onPressed: _isLoadingMore ? null : _loadMore,
              child: _isLoadingMore
                  ? const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Text(widget.loadMoreLabel),
            ),
          ),
      ],
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final caption = context.captionText;
    return SizedBox(
      width: 240,
      child: SelectableText.rich(
        TextSpan(
          style: caption,
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({
    required this.label,
    required this.value,
    required this.truncated,
    required this.l10n,
  });

  final String label;
  final String value;
  final bool truncated;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          truncated ? '$label (${l10n.agentActionsDiagnosticsTruncated})' : label,
          style: context.captionText,
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.controlFillColorDefault,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            value,
            style: context.captionText,
          ),
        ),
      ],
    );
  }
}

String? _executionDuration(AgentActionExecution execution) {
  final startedAt = execution.processStartedAt;
  final finishedAt = execution.finishedAt;
  if (startedAt == null || finishedAt == null) {
    return null;
  }

  final duration = finishedAt.difference(startedAt);
  if (duration.isNegative) {
    return null;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: context.captionText),
    );
  }
}

const List<AgentActionType> _editableDraftTypes = <AgentActionType>[
  AgentActionType.commandLine,
  AgentActionType.executable,
  AgentActionType.script,
  AgentActionType.jar,
  AgentActionType.email,
  AgentActionType.comObject,
  AgentActionType.developer,
];

IconData _iconFor(AgentActionType type) {
  return switch (type) {
    AgentActionType.commandLine => FluentIcons.command_prompt,
    AgentActionType.executable => FluentIcons.processing,
    AgentActionType.script => FluentIcons.script,
    AgentActionType.jar => FluentIcons.file_code,
    AgentActionType.email => FluentIcons.mail,
    AgentActionType.comObject => FluentIcons.code,
    AgentActionType.developer => FluentIcons.developer_tools,
  };
}

IconData _statusIcon(AgentActionExecutionStatus status) {
  return switch (status) {
    AgentActionExecutionStatus.queued => FluentIcons.clock,
    AgentActionExecutionStatus.running => FluentIcons.processing,
    AgentActionExecutionStatus.succeeded => FluentIcons.completed,
    AgentActionExecutionStatus.failed => FluentIcons.error,
    AgentActionExecutionStatus.skipped => FluentIcons.red_eye,
    AgentActionExecutionStatus.cancelled => FluentIcons.cancel,
    AgentActionExecutionStatus.killed => FluentIcons.blocked,
    AgentActionExecutionStatus.timedOut => FluentIcons.timer,
    AgentActionExecutionStatus.interrupted => FluentIcons.warning,
    AgentActionExecutionStatus.unknown => FluentIcons.help,
  };
}

String _actionSubtitle(AgentActionDefinition definition, AppLocalizations l10n) {
  return '${_typeLabel(definition.type, l10n)} - ${_stateLabel(definition.state, l10n)}';
}

String _executionSubtitle(AgentActionExecution execution, AppLocalizations l10n) {
  final exitCode = execution.exitCode == null ? '' : ' - ${l10n.agentActionsExitCode}: ${execution.exitCode}';
  final chunks = execution.stdoutStoredInChunks || execution.stderrStoredInChunks
      ? ' - ${l10n.agentActionsExecutionOutputInChunks}'
      : '';
  return '${l10n.agentActionsRequestedAt}: ${execution.requestedAt.toLocal()}$exitCode$chunks';
}

String _typeLabel(AgentActionType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionType.commandLine => l10n.agentActionsTypeCommandLine,
    AgentActionType.executable => l10n.agentActionsTypeExecutable,
    AgentActionType.script => l10n.agentActionsTypeScript,
    AgentActionType.jar => l10n.agentActionsTypeJar,
    AgentActionType.email => l10n.agentActionsTypeEmail,
    AgentActionType.comObject => l10n.agentActionsTypeComObject,
    AgentActionType.developer => l10n.agentActionsTypeDeveloper,
  };
}

String _stateLabel(AgentActionState state, AppLocalizations l10n) {
  return switch (state) {
    AgentActionState.active => l10n.agentActionsStateActive,
    AgentActionState.paused => l10n.agentActionsStatePaused,
    AgentActionState.disabled => l10n.agentActionsStateDisabled,
    AgentActionState.needsValidation => l10n.agentActionsStateNeedsValidation,
  };
}

String _statusLabel(AgentActionExecutionStatus status, AppLocalizations l10n) {
  return switch (status) {
    AgentActionExecutionStatus.queued => l10n.agentActionsStatusQueued,
    AgentActionExecutionStatus.running => l10n.agentActionsStatusRunning,
    AgentActionExecutionStatus.succeeded => l10n.agentActionsStatusSucceeded,
    AgentActionExecutionStatus.failed => l10n.agentActionsStatusFailed,
    AgentActionExecutionStatus.skipped => l10n.agentActionsStatusSkipped,
    AgentActionExecutionStatus.cancelled => l10n.agentActionsStatusCancelled,
    AgentActionExecutionStatus.killed => l10n.agentActionsStatusKilled,
    AgentActionExecutionStatus.timedOut => l10n.agentActionsStatusTimedOut,
    AgentActionExecutionStatus.interrupted => l10n.agentActionsStatusInterrupted,
    AgentActionExecutionStatus.unknown => l10n.agentActionsStatusUnknown,
  };
}

String _sourceLabel(AgentActionRequestSource source, AppLocalizations l10n) {
  return switch (source) {
    AgentActionRequestSource.localUi => l10n.agentActionsSourceLocalUi,
    AgentActionRequestSource.scheduler => l10n.agentActionsSourceScheduler,
    AgentActionRequestSource.remoteHub => l10n.agentActionsSourceRemoteHub,
    AgentActionRequestSource.appLifecycle => l10n.agentActionsSourceAppLifecycle,
  };
}

String _periodLabel(AgentActionHistoryPeriod period, AppLocalizations l10n) {
  return switch (period) {
    AgentActionHistoryPeriod.all => l10n.agentActionsHistoryPeriodAll,
    AgentActionHistoryPeriod.last24Hours => l10n.agentActionsHistoryPeriodLast24Hours,
    AgentActionHistoryPeriod.last3Days => l10n.agentActionsHistoryPeriodLast3Days,
  };
}

String _triggerDisplayTitle(AgentActionTrigger trigger, AppLocalizations l10n) {
  final name = trigger.name?.trim() ?? '';
  if (name.isEmpty) {
    return l10n.agentActionsTriggerUnnamed;
  }

  return name;
}

String _triggerDeleteConfirmLabel(AgentActionTrigger trigger, AppLocalizations l10n) {
  final name = trigger.name?.trim() ?? '';
  if (name.isEmpty) {
    return '${l10n.agentActionsTriggerUnnamed} (${trigger.id})';
  }

  return name;
}

String _triggerSummaryLine(AgentActionTrigger trigger, AppLocalizations l10n) {
  final typeLabel = _triggerTypeLabel(trigger.type, l10n);
  final statusLabel = trigger.isEnabled ? l10n.agentActionsTriggerEnabled : l10n.agentActionsTriggerDisabled;
  final next = trigger.nextRunAt;
  final scheduleLabel = next == null
      ? l10n.agentActionsTriggerNotScheduled
      : l10n.agentActionsTriggerNextRun(_formatTriggerLocalDateTime(next));

  final base = '$typeLabel · $statusLabel · $scheduleLabel';
  final ianaId = trigger.schedule.timezoneId?.trim();
  final withTimezone = (ianaId == null || ianaId.isEmpty)
      ? base
      : '$base · ${l10n.agentActionsTriggerSummaryTimeZone(ianaId)}';

  if (trigger.isTemporalTrigger && !trigger.schedule.ignoreMissedRuns) {
    return '$withTimezone · ${l10n.agentActionsTriggerSummaryCatchUpEnabled}';
  }

  return withTimezone;
}

String _formatTriggerLocalDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _triggerTypeLabel(AgentActionTriggerType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionTriggerType.manual => l10n.agentActionsTriggerTypeManual,
    AgentActionTriggerType.remote => l10n.agentActionsTriggerTypeRemote,
    AgentActionTriggerType.once => l10n.agentActionsTriggerTypeOnce,
    AgentActionTriggerType.interval => l10n.agentActionsTriggerTypeInterval,
    AgentActionTriggerType.daily => l10n.agentActionsTriggerTypeDaily,
    AgentActionTriggerType.weekly => l10n.agentActionsTriggerTypeWeekly,
    AgentActionTriggerType.monthly => l10n.agentActionsTriggerTypeMonthly,
    AgentActionTriggerType.appStart => l10n.agentActionsTriggerTypeAppStart,
    AgentActionTriggerType.appClose => l10n.agentActionsTriggerTypeAppClose,
  };
}

String? _correctiveActionLabel(
  AgentActionCorrectiveActionKind? correctiveAction,
  AppLocalizations l10n,
) {
  return switch (correctiveAction) {
    AgentActionCorrectiveActionKind.reviewPath => l10n.agentActionsDiagnosticsCorrectivePath,
    AgentActionCorrectiveActionKind.reviewRunner => l10n.agentActionsDiagnosticsCorrectiveRunner,
    AgentActionCorrectiveActionKind.reviewExitCode => l10n.agentActionsDiagnosticsCorrectiveExitCode,
    AgentActionCorrectiveActionKind.reviewQueue => l10n.agentActionsDiagnosticsCorrectiveQueue,
    AgentActionCorrectiveActionKind.reviewTimeout => l10n.agentActionsDiagnosticsCorrectiveTimeout,
    AgentActionCorrectiveActionKind.retryKill => l10n.agentActionsDiagnosticsCorrectiveKill,
    AgentActionCorrectiveActionKind.reviewDefinitionValidation =>
      l10n.agentActionsDiagnosticsCorrectiveDefinitionValidation,
    AgentActionCorrectiveActionKind.reviewPreflight => l10n.agentActionsDiagnosticsCorrectivePreflight,
    AgentActionCorrectiveActionKind.reviewStartProcess => l10n.agentActionsDiagnosticsCorrectiveStartProcess,
    AgentActionCorrectiveActionKind.reviewRuntime => l10n.agentActionsDiagnosticsCorrectiveRuntime,
    _ => null,
  };
}

String _testDiagnosticLabel(String key, AppLocalizations l10n) {
  return switch (key) {
    'engine' => l10n.agentActionsTestPreviewDiagnosticEngine,
    'connection_label' => l10n.agentActionsTestPreviewDiagnosticConnectionLabel,
    'catalog_connection_count' => l10n.agentActionsTestPreviewDiagnosticCatalogCount,
    'used_default_config_path' => l10n.agentActionsTestPreviewDiagnosticDefaultConfig,
    'phase' => l10n.agentActionsDiagnosticsFailurePhase,
    _ => key,
  };
}

String _testDiagnosticValue(String key, Object? value, AppLocalizations l10n) {
  if (value is bool) {
    return value ? l10n.agentActionsTestPreviewDiagnosticYes : l10n.agentActionsTestPreviewDiagnosticNo;
  }
  if (key == 'phase' && value is String && value.trim().isNotEmpty) {
    return _localizedFailurePhase(value, l10n);
  }
  return value?.toString() ?? '-';
}

String _localizedFailurePhase(String phase, AppLocalizations l10n) {
  return switch (phase.trim()) {
    'execution_preflight' => l10n.agentActionsFailurePhaseExecutionPreflight,
    'definition_validation' => l10n.agentActionsFailurePhaseDefinitionValidation,
    'start_process' => l10n.agentActionsFailurePhaseStartProcess,
    'stdin_setup' => l10n.agentActionsFailurePhaseStdinSetup,
    'process_runtime' => l10n.agentActionsFailurePhaseProcessRuntime,
    'process_exit' => l10n.agentActionsFailurePhaseProcessExit,
    'queue' => l10n.agentActionsFailurePhaseQueue,
    'timeout' => l10n.agentActionsFailurePhaseTimeout,
    'authorization' => l10n.agentActionsFailurePhaseAuthorization,
    'validation' => l10n.agentActionsFailurePhaseValidation,
    'lookup' => l10n.agentActionsFailurePhaseLookup,
    'cancel' => l10n.agentActionsFailurePhaseCancel,
    'platform_check' => l10n.agentActionsFailurePhasePlatformCheck,
    'smtp_send' => l10n.agentActionsFailurePhaseSmtpSend,
    'execution_send' => l10n.agentActionsFailurePhaseExecutionSend,
    'elevated_submit' => l10n.agentActionsFailurePhaseElevatedSubmit,
    'bootstrap_reconciliation' => l10n.agentActionsFailurePhaseBootstrapReconciliation,
    _ => _failurePhaseFallbackLabel(phase),
  };
}

String _failurePhaseFallbackLabel(String phase) {
  final normalized = phase.trim();
  if (normalized.isEmpty) {
    return phase;
  }

  return normalized
      .split('_')
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) => '${segment[0].toUpperCase()}${segment.substring(1)}',
      )
      .join(' ');
}
