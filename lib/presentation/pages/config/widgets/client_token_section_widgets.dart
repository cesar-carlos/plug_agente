part of 'client_token_section.dart';

class _TokenFormErrorAnnouncer extends StatefulWidget {
  const _TokenFormErrorAnnouncer({
    required this.formError,
    required this.providerError,
    required this.child,
  });

  final String formError;
  final String providerError;
  final Widget child;

  @override
  State<_TokenFormErrorAnnouncer> createState() => _TokenFormErrorAnnouncerState();
}

class _TokenFormErrorAnnouncerState extends State<_TokenFormErrorAnnouncer> {
  @override
  void didUpdateWidget(covariant _TokenFormErrorAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _announceIfNew(widget.formError, oldWidget.formError);
    _announceIfNew(widget.providerError, oldWidget.providerError);
  }

  void _announceIfNew(String next, String previous) {
    if (next.isEmpty || next == previous) {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      next,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CreateTokenDialogContent extends StatelessWidget {
  const _CreateTokenDialogContent({
    required this.isCompact,
    required this.agentFocusNode,
    required this.nameController,
    required this.clientIdController,
    required this.agentIdController,
    required this.payloadController,
    required this.rules,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onToggleAllTables,
    required this.onToggleAllViews,
    required this.onToggleAllPermissions,
    required this.onAddRule,
    required this.onExportRules,
    required this.onImportRules,
    required this.isImportingRules,
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onDismissCreatedToken,
    required this.onFieldSubmitted,
  });

  final bool isCompact;
  final FocusNode agentFocusNode;
  final TextEditingController nameController;
  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final TextEditingController payloadController;
  final List<ClientTokenRuleDraft> rules;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final ValueChanged<bool> onToggleAllTables;
  final ValueChanged<bool> onToggleAllViews;
  final ValueChanged<bool> onToggleAllPermissions;
  final VoidCallback onAddRule;
  final VoidCallback onExportRules;
  final VoidCallback onImportRules;
  final bool isImportingRules;
  final ValueChanged<int> onEditRule;
  final ValueChanged<int> onDeleteRule;
  final VoidCallback onDismissCreatedToken;
  final VoidCallback onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _TokenFormErrorAnnouncer(
      formError: formError,
      providerError: providerError,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: AppTextField(
                label: l10n.ctFieldName,
                controller: nameController,
                hint: l10n.ctHintName,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _TokenIdentityFields(
              clientIdController: clientIdController,
              agentIdController: agentIdController,
              agentFocusNode: agentFocusNode,
              isCompact: isCompact,
              onAgentSubmitted: onFieldSubmitted,
            ),
            const SizedBox(height: AppSpacing.md),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: AppTextField(
                label: l10n.ctFieldPayloadJsonOptional,
                controller: payloadController,
                hint: l10n.ctHintPayloadJson,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _FlagCheckbox(
                  focusOrder: 5,
                  label: l10n.ctFlagAllTables,
                  value: allTables,
                  onChanged: onToggleAllTables,
                ),
                _FlagCheckbox(
                  focusOrder: 6,
                  label: l10n.ctFlagAllViews,
                  value: allViews,
                  onChanged: onToggleAllViews,
                ),
                _FlagCheckbox(
                  focusOrder: 7,
                  label: l10n.ctFlagAllPermissions,
                  value: allPermissions,
                  onChanged: onToggleAllPermissions,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SettingsSectionTitle(
                    title: l10n.ctSectionRulesByResource,
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.end,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(8),
                        child: isImportingRules
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            : AppButton(
                                label: l10n.ctButtonImportRules,
                                isPrimary: false,
                                icon: FluentIcons.upload,
                                onPressed: allPermissions ? null : onImportRules,
                              ),
                      ),
                      if (rules.isNotEmpty)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(9),
                          child: AppButton(
                            label: l10n.ctButtonExportRules,
                            isPrimary: false,
                            icon: FluentIcons.download,
                            onPressed: onExportRules,
                          ),
                        ),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(10),
                        child: AppButton(
                          label: l10n.ctButtonAddRule,
                          isPrimary: false,
                          icon: FluentIcons.add,
                          onPressed: allPermissions ? null : onAddRule,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (rules.isEmpty)
              Text(l10n.ctNoRulesAdded)
            else
              ClientTokenRulesGrid(
                rules: rules,
                onEdit: onEditRule,
                onDelete: onDeleteRule,
              ),
            _TokenFeedbackPanel(
              formError: formError,
              providerError: providerError,
              lastCreatedToken: lastCreatedToken,
              onDismissCreatedToken: onDismissCreatedToken,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTokenDialogFooter extends StatelessWidget {
  const _CreateTokenDialogFooter({
    required this.isCreating,
    required this.submitLabel,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool isCreating;
  final String submitLabel;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(200),
          child: AppButton(
            label: l10n.btnCancel,
            isPrimary: false,
            onPressed: isCreating ? null : onCancel,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FocusTraversalOrder(
          order: const NumericFocusOrder(210),
          child: AppButton(
            label: submitLabel,
            isLoading: isCreating,
            onPressed: isCreating ? null : onSubmit,
          ),
        ),
      ],
    );
  }
}

class _TokenListFilters extends StatelessWidget {
  const _TokenListFilters({
    required this.clientFilterController,
    required this.tokenStatusFilter,
    required this.tokenSortOption,
    required this.onClientFilterChanged,
    required this.statusLabelBuilder,
    required this.sortLabelBuilder,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final TextEditingController clientFilterController;
  final ClientTokenStatusFilter tokenStatusFilter;
  final ClientTokenSortOption tokenSortOption;
  final ValueChanged<String> onClientFilterChanged;
  final String Function(ClientTokenStatusFilter) statusLabelBuilder;
  final String Function(ClientTokenSortOption) sortLabelBuilder;
  final ValueChanged<ClientTokenStatusFilter> onStatusChanged;
  final ValueChanged<ClientTokenSortOption> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: l10n.ctFilterClientId,
            controller: clientFilterController,
            hint: l10n.ctHintClientId,
            onChanged: onClientFilterChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: AppDropdown<ClientTokenStatusFilter>(
            label: l10n.ctFilterStatus,
            value: tokenStatusFilter,
            items: ClientTokenStatusFilter.values
                .map(
                  (item) => ComboBoxItem<ClientTokenStatusFilter>(
                    value: item,
                    child: Text(statusLabelBuilder(item)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: AppDropdown<ClientTokenSortOption>(
            label: l10n.ctFilterSort,
            value: tokenSortOption,
            items: ClientTokenSortOption.values
                .map(
                  (item) => ComboBoxItem<ClientTokenSortOption>(
                    value: item,
                    child: Text(sortLabelBuilder(item)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onSortChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        AppButton(
          label: l10n.ctButtonClearFilters,
          isPrimary: false,
          icon: FluentIcons.clear_filter,
          onPressed: onClearFilters,
        ),
      ],
    );
  }
}

class _TokenIdentityFields extends StatelessWidget {
  const _TokenIdentityFields({
    required this.clientIdController,
    required this.agentIdController,
    required this.agentFocusNode,
    required this.isCompact,
    required this.onAgentSubmitted,
  });

  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final FocusNode agentFocusNode;
  final bool isCompact;
  final VoidCallback onAgentSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final Widget clientField = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: AppTextField(
        label: l10n.ctFieldClientId,
        controller: clientIdController,
        hint: l10n.ctHintClientId,
        readOnly: true,
        suffixIcon: _CopyValueButton(value: clientIdController.text),
      ),
    );

    final Widget agentField = FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: AppTextField(
        label: l10n.ctFieldAgentIdOptional,
        controller: agentIdController,
        hint: l10n.ctHintAgentId,
        focusNode: agentFocusNode,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onAgentSubmitted(),
      ),
    );

    if (isCompact) {
      return Column(
        children: [
          clientField,
          const SizedBox(height: AppSpacing.md),
          agentField,
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: clientField),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 2, child: agentField),
      ],
    );
  }
}

class _CopyValueButton extends StatelessWidget {
  const _CopyValueButton({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(FluentIcons.copy, size: 16),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
      },
    );
  }
}

class _TokenFeedbackPanel extends StatelessWidget {
  const _TokenFeedbackPanel({
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onDismissCreatedToken,
  });

  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final VoidCallback onDismissCreatedToken;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedbackWidgets = <Widget>[
      if (formError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: formError,
        ),
      if (providerError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: providerError,
        ),
      if (lastCreatedToken != null)
        InlineFeedbackCard(
          severity: InfoBarSeverity.success,
          title: l10n.ctMsgTokenCreatedCopyNow,
          content: SelectableText(lastCreatedToken!),
          onDismiss: onDismissCreatedToken,
        ),
    ];

    if (feedbackWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: List<Widget>.generate(feedbackWidgets.length, (index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == feedbackWidgets.length - 1 ? 0 : AppSpacing.md,
            ),
            child: feedbackWidgets[index],
          );
        }),
      ),
    );
  }
}

class _FlagCheckbox extends StatelessWidget {
  const _FlagCheckbox({
    required this.focusOrder,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final double focusOrder;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: Checkbox(
        checked: value,
        onChanged: (isChecked) => onChanged(isChecked ?? false),
        content: Text(label),
      ),
    );
  }
}

List<AppGridColumn> _tokenGridColumns(AppLocalizations l10n) => [
  AppGridColumn(label: l10n.ctLabelClient, flex: 3),
  AppGridColumn(label: l10n.ctLabelId, flex: 4),
  AppGridColumn(label: l10n.ctLabelStatus, flex: 2),
  AppGridColumn(label: l10n.ctLabelScope, flex: 2),
  AppGridColumn(
    label: l10n.ctLabelCreatedAt,
    flex: 3,
    alignment: Alignment.center,
  ),
  AppGridColumn(
    label: l10n.ctGridColumnActions,
    flex: 4,
    alignment: Alignment.center,
  ),
];

class _TokenSummaryGrid extends StatelessWidget {
  const _TokenSummaryGrid({
    required this.tokens,
    required this.isRevokingToken,
    required this.isDeletingToken,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onRevoke,
    required this.onDelete,
    this.scrollController,
  });

  final List<ClientTokenSummary> tokens;
  final ScrollController? scrollController;
  final bool Function(String tokenId) isRevokingToken;
  final bool Function(String tokenId) isDeletingToken;
  final ValueChanged<ClientTokenSummary> onViewDetails;
  final ValueChanged<ClientTokenSummary> onCopyClientToken;
  final ValueChanged<ClientTokenSummary> onEdit;
  final ValueChanged<ClientTokenSummary> onRevoke;
  final ValueChanged<ClientTokenSummary> onDelete;

  String _buildScopeLabel(ClientTokenSummary token, AppLocalizations l10n) {
    if (token.allPermissions) return l10n.ctScopeAllPermissions;
    final scopes = <String>[
      if (token.allTables) l10n.ctScopeTables,
      if (token.allViews) l10n.ctScopeViews,
    ];
    return scopes.isEmpty ? l10n.ctScopeRestricted : scopes.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppDataGridScrollable<ClientTokenSummary>(
      columns: _tokenGridColumns(l10n),
      rows: tokens,
      scrollController: scrollController,
      rowCells: (token) => [
        Tooltip(
          message: token.name.isNotEmpty ? token.clientId : '',
          child: SelectableText(token.name.isNotEmpty ? token.name : token.clientId),
        ),
        SelectableText(token.id),
        Text(
          token.isRevoked ? l10n.ctStatusRevoked : l10n.ctStatusActive,
        ),
        Text(_buildScopeLabel(token, l10n)),
        Text(
          DateFormat('dd/MM/yyyy HH:mm').format(token.createdAt.toLocal()),
        ),
        _TokenRowActions(
          l10n: l10n,
          token: token,
          isRevoking: isRevokingToken(token.id),
          isDeleting: isDeletingToken(token.id),
          onViewDetails: () => onViewDetails(token),
          onCopyClientToken: () => onCopyClientToken(token),
          onEdit: () => onEdit(token),
          onRevoke: token.isRevoked ? null : () => onRevoke(token),
          onDelete: () => onDelete(token),
        ),
      ],
    );
  }
}

class _TokenRowActions extends StatelessWidget {
  const _TokenRowActions({
    required this.l10n,
    required this.token,
    required this.isRevoking,
    required this.isDeleting,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onDelete,
    this.onRevoke,
  });

  final AppLocalizations l10n;
  final ClientTokenSummary token;
  final bool isRevoking;
  final bool isDeleting;
  final VoidCallback onViewDetails;
  final VoidCallback onCopyClientToken;
  final VoidCallback onEdit;
  final VoidCallback? onRevoke;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final revokeTooltip = token.isRevoked ? l10n.ctButtonRevoked : l10n.ctButtonRevoke;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Tooltip(
          message: l10n.ctTooltipEditToken,
          child: Semantics(
            button: true,
            label: l10n.ctButtonEdit,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: onEdit,
            ),
          ),
        ),
        Tooltip(
          message: l10n.ctButtonViewDetails,
          child: Semantics(
            button: true,
            label: l10n.ctButtonViewDetails,
            child: IconButton(
              icon: const Icon(FluentIcons.view),
              onPressed: onViewDetails,
            ),
          ),
        ),
        Tooltip(
          message: l10n.ctTooltipCopyClientToken,
          child: Semantics(
            button: true,
            label: l10n.ctButtonCopyClientToken,
            child: IconButton(
              icon: const Icon(FluentIcons.copy),
              onPressed: onCopyClientToken,
            ),
          ),
        ),
        Tooltip(
          message: revokeTooltip,
          child: Semantics(
            button: true,
            label: revokeTooltip,
            child: isRevoking
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(FluentIcons.block_contact),
                    onPressed: onRevoke,
                  ),
          ),
        ),
        Tooltip(
          message: l10n.ctButtonDelete,
          child: Semantics(
            button: true,
            label: l10n.ctButtonDelete,
            child: isDeleting
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(FluentIcons.delete),
                    onPressed: onDelete,
                  ),
          ),
        ),
      ],
    );
  }
}
