part of 'agent_actions_page.dart';

IAppSettingsStore? _settingsStore() {
  return getIt.isRegistered<IAppSettingsStore>() ? getIt<IAppSettingsStore>() : null;
}

class _AgentActionsStatusStrip extends StatelessWidget {
  const _AgentActionsStatusStrip({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final statusWidgets = <Widget>[
      if (!provider.isFeatureEnabled)
        InfoBar(
          title: Text(l10n.agentActionsDisabledTitle),
          content: Text(l10n.agentActionsDisabledMessage),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ..._runtimeSubsystemStatusWidgets(provider, l10n),
      ..._schedulerOperationalIssueWidgets(provider, l10n),
      ..._comObjectInvocationWarningWidgets(provider, l10n),
      if (provider.errorMessage != null)
        InfoBar(
          title: Text(l10n.agentActionsErrorTitle),
          content: SelectableText(provider.errorMessage!),
          severity: InfoBarSeverity.error,
          isLong: true,
        ),
    ];

    if (statusWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 170),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: statusWidgets.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => statusWidgets[index],
      ),
    );
  }
}

class _AgentActionsActionsTab extends StatelessWidget {
  const _AgentActionsActionsTab({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    required this.onCreateAction,
    required this.onShowDetails,
    required this.onEditAction,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;
  final VoidCallback onCreateAction;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentActionsToolbarCard(
          provider: provider,
          l10n: l10n,
          onCreateAction: provider.canSaveAction ? onCreateAction : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _AgentActionsList(
            provider: provider,
            l10n: l10n,
            uiPreferences: uiPreferences,
            onCreateAction: onCreateAction,
            onShowDetails: onShowDetails,
            onAddTrigger: (definition) {
              provider.selectAction(definition.id);
              provider.clearTriggerOperationError();
              unawaited(
                showAgentActionTriggerSaveDialog(
                  context: context,
                  provider: provider,
                  l10n: l10n,
                  actionId: definition.id,
                ),
              );
            },
            onEditAction: onEditAction,
          ),
        ),
      ],
    );
  }
}

class _AgentActionsHistoryTab extends StatelessWidget {
  const _AgentActionsHistoryTab({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

  @override
  Widget build(BuildContext context) {
    final selected = provider.selectedDefinition;
    if (selected == null) {
      return AgentActionsEmptySelectionPanel(
        detailScrollKey: _AgentActionsPageKeys.detailScroll,
        content: Center(
          child: Text(
            l10n.agentActionsEmptySelection,
            style: context.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(selected.type), size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(selected.name, style: context.sectionTitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _AgentActionsHistoryFilters(provider: provider, l10n: l10n, uiPreferences: uiPreferences),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _AgentActionExecutionList(
              executions: provider.filteredSelectedExecutions,
              provider: provider,
              l10n: l10n,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentActionsSettingsTab extends StatelessWidget {
  const _AgentActionsSettingsTab({
    required this.provider,
    required this.l10n,
    required this.runtimeCapabilities,
    required this.runtimeDiagnostics,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final RuntimeCapabilities runtimeCapabilities;
  final RuntimeDetectionDiagnostics? runtimeDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AgentActionsSummaryCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        ..._elevatedRunnerStatusWidgets(provider, l10n),
        AgentActionsPreflightSettingsCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        AgentActionsDangerousCommandWarnCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        AgentActionsRetentionCard(l10n: l10n, provider: provider),
        if (runtimeCapabilities.isDegraded ||
            runtimeCapabilities.isUnsupported ||
            runtimeDiagnostics?.source == RuntimeDetectionSource.detectionFailed) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionsRuntimeSupportCard(
            capabilities: runtimeCapabilities,
            diagnostics: runtimeDiagnostics,
          ),
        ],
      ],
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
    required this.uiPreferences,
    required this.onCreateAction,
    required this.onShowDetails,
    required this.onAddTrigger,
    required this.onEditAction,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;
  final VoidCallback onCreateAction;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onAddTrigger;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const Center(child: ProgressRing());
    }
    if (provider.definitions.isEmpty) {
      return AppCard(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.processing,
                  size: 36,
                  color: FluentTheme.of(context).accentColor,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.agentActionsEmptyActions,
                  style: context.sectionTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${_typeLabel(AgentActionType.commandLine, l10n)}, '
                  '${_typeLabel(AgentActionType.executable, l10n)}, '
                  '${_typeLabel(AgentActionType.script, l10n)}',
                  style: context.bodyMuted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: provider.canSaveAction ? onCreateAction : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.add),
                      const SizedBox(width: AppSpacing.xs),
                      Text(l10n.agentActionsFormNew),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final visibleDefinitions = provider.filteredDefinitions;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AgentActionsDefinitionFilters(provider: provider, l10n: l10n, uiPreferences: uiPreferences),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AppDataGridScrollable<AgentActionDefinition>(
              columns: [
                AppGridColumn(label: l10n.agentActionsFormName, flex: 4),
                AppGridColumn(label: l10n.agentActionsFormType, flex: 2),
                AppGridColumn(label: l10n.agentActionsFormState, flex: 2),
                AppGridColumn(label: l10n.agentActionsGridColumnRisksTriggers, flex: 2),
                AppGridColumn(label: l10n.ctGridColumnActions, flex: 5, alignment: Alignment.centerRight),
              ],
              rows: visibleDefinitions,
              rowHeight: 52,
              emptyMessage: l10n.agentActionsListFilterEmpty,
              rowKey: (definition) => ValueKey<String>('agent_action_definition_row_${definition.id}'),
              isRowSelected: (definition) => provider.selectedDefinition?.id == definition.id,
              onRowPressed: (definition) => provider.selectAction(definition.id),
              rowCells: (definition) {
                final riskDescriptors = collectAgentActionRiskDescriptors(
                  definition: definition,
                  l10n: l10n,
                  runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
                  editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
                  needsValidation: definition.state == AgentActionState.needsValidation,
                  secretPlaceholderNames: definition.id == provider.selectedActionId
                      ? provider.selectedSecretPlaceholderNames
                      : AgentActionSecretPlaceholderScanner.collectFromDefinition(definition),
                  triggers: definition.id == provider.selectedActionId
                      ? provider.triggers
                      : const <AgentActionTrigger>[],
                );
                return [
                  _DefinitionNameCell(definition: definition, l10n: l10n),
                  Text(_definitionTypeLabel(definition, l10n), overflow: TextOverflow.ellipsis),
                  Text(_stateLabel(definition.state, l10n), overflow: TextOverflow.ellipsis),
                  if (riskDescriptors.isEmpty)
                    Text(_actionSubtitle(definition, l10n), style: context.captionText)
                  else
                    AgentActionRiskChips(descriptors: riskDescriptors),
                  _DefinitionRowActions(
                    definition: definition,
                    provider: provider,
                    l10n: l10n,
                    onShowDetails: onShowDetails,
                    onAddTrigger: onAddTrigger,
                    onEditAction: onEditAction,
                  ),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DefinitionNameCell extends StatelessWidget {
  const _DefinitionNameCell({
    required this.definition,
    required this.l10n,
  });

  final AgentActionDefinition definition;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_definitionIconFor(definition), size: 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(definition.name, overflow: TextOverflow.ellipsis),
              Text(definition.id, style: context.captionText, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _DefinitionRowActions extends StatelessWidget {
  const _DefinitionRowActions({
    required this.definition,
    required this.provider,
    required this.l10n,
    required this.onShowDetails,
    required this.onAddTrigger,
    required this.onEditAction,
  });

  final AgentActionDefinition definition;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onAddTrigger;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.agentActionsRunSelected,
          child: IconButton(
            icon: provider.isRunning
                ? const SizedBox.square(
                    dimension: 14,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Icon(FluentIcons.play),
            onPressed: provider.canRunDefinition(definition)
                ? () {
                    provider.selectAction(definition.id);
                    unawaited(
                      _runSelectedActionWithDangerousCommandCheck(
                        context,
                        provider,
                        l10n,
                        definition: definition,
                      ),
                    );
                  }
                : null,
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTestSelected,
          child: IconButton(
            icon: provider.isTesting
                ? const SizedBox.square(
                    dimension: 14,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Icon(FluentIcons.test_beaker),
            onPressed: provider.canTestDefinition(definition)
                ? () {
                    provider.selectAction(definition.id);
                    unawaited(provider.testSelectedAction());
                  }
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        DropDownButton(
          key: ValueKey<String>('agent_action_definition_more_${definition.id}'),
          buttonBuilder: (context, onOpen) => IconButton(
            icon: const Icon(FluentIcons.more),
            onPressed: onOpen,
          ),
          items: [
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_details_${definition.id}'),
              leading: const Icon(FluentIcons.view),
              text: Text(l10n.ctButtonViewDetails),
              onPressed: () {
                provider.selectAction(definition.id);
                onShowDetails(definition);
              },
            ),
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_trigger_${definition.id}'),
              leading: const Icon(FluentIcons.add_event),
              text: Text(l10n.agentActionsTriggerAdd),
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.selectAction(definition.id);
                      onAddTrigger(definition);
                    }
                  : null,
            ),
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_edit_${definition.id}'),
              leading: const Icon(FluentIcons.edit),
              text: Text(l10n.ctButtonEdit),
              onPressed: isAgentActionTypeEditableInUi(definition.type) ? () => onEditAction(definition) : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.delete),
              text: Text(l10n.agentActionsDeleteSelected),
              onPressed: provider.canDeleteDefinition(definition)
                  ? () {
                      provider.selectAction(definition.id);
                      unawaited(_confirmDelete(context, provider, definition, l10n));
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _AgentActionsDefinitionFilters extends StatefulWidget {
  const _AgentActionsDefinitionFilters({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

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

    return AppFilterBar(
      children: [
        SizedBox(
          width: 220,
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
            onChanged: (type) {
              provider.setDefinitionTypeFilter(type);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionTypeFilter, type?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: AppDropdown<AgentActionState?>(
            label: l10n.agentActionsFormState,
            value: provider.definitionStateFilter,
            items: [
              ComboBoxItem<AgentActionState?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionState.values.map(
                (state) => ComboBoxItem<AgentActionState?>(
                  value: state,
                  child: Text(_stateLabel(state, l10n)),
                ),
              ),
            ],
            onChanged: (state) {
              provider.setDefinitionStateFilter(state);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionStateFilter, state?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 260,
          child: AppTextField(
            label: l10n.agentActionsListFilterSearch,
            controller: _searchController,
            onChanged: (query) {
              provider.setDefinitionSearchQuery(query);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionSearch, query.trim()),
              );
            },
            textInputAction: TextInputAction.search,
          ),
        ),
        Button(
          onPressed: provider.hasDefinitionListFilters
              ? () {
                  provider.clearDefinitionFilters();
                  unawaited(
                    widget.uiPreferences.removeKeys([
                      AgentActionsUiPreferenceKeys.definitionTypeFilter,
                      AgentActionsUiPreferenceKeys.definitionStateFilter,
                      AgentActionsUiPreferenceKeys.definitionSearch,
                    ]),
                  );
                }
              : null,
          child: Text(l10n.ctButtonClearFilters),
        ),
      ],
    );
  }
}

class _SelectedActionDetailContent extends StatelessWidget {
  const _SelectedActionDetailContent({
    required this.provider,
    required this.l10n,
    required this.definition,
    required this.lastTestCanRun,
    required this.onEditAction,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionDefinition definition;
  final bool lastTestCanRun;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_definitionIconFor(definition), size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(definition.name, style: context.sectionTitle)),
            Text(_stateLabel(definition.state, l10n), style: context.bodyMuted),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: l10n.ctButtonEdit,
              child: Semantics(
                button: true,
                label: l10n.ctButtonEdit,
                child: IconButton(
                  icon: const Icon(FluentIcons.edit),
                  onPressed: isAgentActionTypeEditableInUi(definition.type) ? () => onEditAction(definition) : null,
                ),
              ),
            ),
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
        ..._dangerousCommandRunGuidance(
          provider: provider,
          definition: definition,
          l10n: l10n,
        ),
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
            _Pill(text: _definitionTypeLabel(definition, l10n)),
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
            content: Text(
              provider.isPreflightValidForDefinition(definition)
                  ? l10n.agentActionsPreflightReadyForActivation
                  : l10n.agentActionsNeedsValidationMessage,
            ),
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
                _definitionTypeLabel(definition, l10n),
              ),
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
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
  });

  final List<AgentActionExecution> executions;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;

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
              key: ValueKey<String>('agent_action_trigger_edit_${trigger.id}'),
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
              key: ValueKey<String>('agent_action_trigger_delete_${trigger.id}'),
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
  final confirmed = await AppConfirmDialog.show(
    context: context,
    title: l10n.agentActionsTriggerDeleteConfirmTitle,
    message: l10n.agentActionsTriggerDeleteConfirmMessage(label),
    confirmLabel: l10n.agentActionsTriggerDeleteConfirm,
    cancelLabel: l10n.agentActionsTriggerDeleteCancel,
  );

  if (confirmed) {
    await provider.deleteTrigger(trigger.id);
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  AgentActionsProvider provider,
  AgentActionDefinition definition,
  AppLocalizations l10n,
) async {
  final confirmed = await AppConfirmDialog.show(
    context: context,
    title: l10n.agentActionsDeleteConfirmTitle,
    message: l10n.agentActionsDeleteConfirmMessage(definition.name),
    confirmLabel: l10n.agentActionsDeleteConfirm,
    cancelLabel: l10n.agentActionsDeleteCancel,
  );

  if (confirmed) {
    await provider.deleteSelectedAction();
  }
}

Future<void> _runSelectedActionWithDangerousCommandCheck(
  BuildContext context,
  AgentActionsProvider provider,
  AppLocalizations l10n, {
  AgentActionDefinition? definition,
}) async {
  final target = definition ?? provider.selectedDefinition;
  if (target == null || !provider.canRunDefinition(target)) {
    return;
  }

  provider.selectAction(target.id);
  final assessment = provider.assessDangerousCommandForRun(target);
  if (assessment.isBlocked) {
    provider.reportDangerousCommandBlocked(l10n.agentActionsDangerousCommandBlockedMessage);
    return;
  }

  if (assessment.requiresConfirmation) {
    final match = assessment.match;
    if (match == null) {
      return;
    }

    final confirmed = await confirmDangerousCommandRun(
      context: context,
      l10n: l10n,
      patternId: match.patternId,
      patternDescription: match.description,
    );
    if (!confirmed) {
      return;
    }
  }

  await provider.runSelectedAction();
}

List<Widget> _dangerousCommandRunGuidance({
  required AgentActionsProvider provider,
  required AgentActionDefinition definition,
  required AppLocalizations l10n,
}) {
  final assessment = provider.assessDangerousCommandForRun(definition);
  if (assessment.policy == AgentActionDangerousCommandRunPolicy.allow) {
    return const <Widget>[];
  }

  final match = assessment.match;
  if (match == null) {
    return const <Widget>[];
  }

  if (assessment.isBlocked) {
    return <Widget>[
      InfoBar(
        key: ValueKey<String>('agent_action_dangerous_command_blocked_${definition.id}'),
        title: Text(l10n.agentActionsDangerousCommandBlockedTitle),
        content: Text(l10n.agentActionsDangerousCommandBlockedMessage),
        severity: InfoBarSeverity.error,
        isLong: true,
      ),
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  return <Widget>[
    InfoBar(
      key: ValueKey<String>('agent_action_dangerous_command_warn_${definition.id}'),
      title: Text(l10n.agentActionsDangerousCommandWarnTitle),
      content: Text(
        l10n.agentActionsDangerousCommandWarnMessage(
          match.patternId,
          match.description,
        ),
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.sm),
  ];
}

class _AgentActionsHistoryFilters extends StatefulWidget {
  const _AgentActionsHistoryFilters({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

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
            onChanged: (status) {
              provider.setHistoryStatusFilter(status);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyStatusFilter, status?.name),
              );
            },
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
            onChanged: (source) {
              provider.setHistorySourceFilter(source);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historySourceFilter, source?.name),
              );
            },
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
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyPeriodFilter, period.name),
              );
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
            onChanged: (phase) {
              provider.setHistoryFailurePhaseFilter(phase);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyFailurePhaseFilter, phase),
              );
            },
          ),
        ),
        SizedBox(
          width: 280,
          child: AppTextField(
            label: l10n.agentActionsHistoryFilterSearch,
            controller: _searchController,
            onChanged: (query) {
              provider.setHistorySearchQuery(query);
              unawaited(widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historySearch, query.trim()));
            },
            textInputAction: TextInputAction.search,
          ),
        ),
      ],
    );
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

const List<_AgentActionDraftKind> _editableDraftKinds = <_AgentActionDraftKind>[
  _AgentActionDraftKind.commandLine,
  _AgentActionDraftKind.executable,
  _AgentActionDraftKind.script,
  _AgentActionDraftKind.jar,
  _AgentActionDraftKind.email,
  _AgentActionDraftKind.comObject,
  _AgentActionDraftKind.developer,
  _AgentActionDraftKind.powerShell,
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

IconData _definitionIconFor(AgentActionDefinition definition) {
  return _isPowerShellDefinition(definition) ? FluentIcons.command_prompt : _iconFor(definition.type);
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
  return '${_definitionTypeLabel(definition, l10n)} - ${_stateLabel(definition.state, l10n)}';
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

String _definitionTypeLabel(AgentActionDefinition definition, AppLocalizations l10n) {
  return _isPowerShellDefinition(definition) ? l10n.agentActionsTypePowerShell : _typeLabel(definition.type, l10n);
}

bool _isPowerShellDefinition(AgentActionDefinition definition) {
  return switch (definition.config) {
    CommandLineActionConfig(:final command) => PowerShellCommandLine.tryUnwrapInlineCommand(command) != null,
    ScriptActionConfig(:final scriptPath) => PowerShellCommandLine.isPowerShellScriptPath(scriptPath.originalPath),
    _ => false,
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
