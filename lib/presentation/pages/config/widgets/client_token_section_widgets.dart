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
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onDismissCreatedToken,
    required this.onFieldSubmitted,
  });

  final bool isCompact;
  final FocusNode agentFocusNode;
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
  final ValueChanged<int> onEditRule;
  final ValueChanged<int> onDeleteRule;
  final VoidCallback onDismissCreatedToken;
  final VoidCallback onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return _TokenFormErrorAnnouncer(
      formError: formError,
      providerError: providerError,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TokenIdentityFields(
              clientIdController: clientIdController,
              agentIdController: agentIdController,
              agentFocusNode: agentFocusNode,
              isCompact: isCompact,
              onAgentSubmitted: onFieldSubmitted,
            ),
            const SizedBox(height: AppSpacing.md),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: AppTextField(
                label: AppStrings.ctFieldPayloadJsonOptional,
                controller: payloadController,
                hint: AppStrings.ctHintPayloadJson,
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
                  focusOrder: 4,
                  label: AppStrings.ctFlagAllTables,
                  value: allTables,
                  onChanged: onToggleAllTables,
                ),
                _FlagCheckbox(
                  focusOrder: 5,
                  label: AppStrings.ctFlagAllViews,
                  value: allViews,
                  onChanged: onToggleAllViews,
                ),
                _FlagCheckbox(
                  focusOrder: 6,
                  label: AppStrings.ctFlagAllPermissions,
                  value: allPermissions,
                  onChanged: onToggleAllPermissions,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: SettingsSectionTitle(
                    title: AppStrings.ctSectionRulesByResource,
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(7),
                  child: AppButton(
                    label: AppStrings.ctButtonAddRule,
                    isPrimary: false,
                    icon: FluentIcons.add,
                    onPressed: allPermissions ? null : onAddRule,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (rules.isEmpty)
              const Text(AppStrings.ctNoRulesAdded)
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(200),
          child: AppButton(
            label: AppStrings.btnCancel,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: AppStrings.ctFilterClientId,
            controller: clientFilterController,
            hint: AppStrings.ctHintClientId,
            onChanged: onClientFilterChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: AppDropdown<ClientTokenStatusFilter>(
            label: AppStrings.ctFilterStatus,
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
            label: AppStrings.ctFilterSort,
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
          label: AppStrings.ctButtonClearFilters,
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
    final Widget clientField = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: AppTextField(
        label: AppStrings.ctFieldClientId,
        controller: clientIdController,
        hint: AppStrings.ctHintClientId,
        readOnly: true,
        suffixIcon: _CopyValueButton(value: clientIdController.text),
      ),
    );

    final Widget agentField = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: AppTextField(
        label: AppStrings.ctFieldAgentIdOptional,
        controller: agentIdController,
        hint: AppStrings.ctHintAgentId,
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
          title: AppStrings.ctMsgTokenCreatedCopyNow,
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

const _tokenGridColumns = [
  AppGridColumn(label: AppStrings.ctLabelClient, flex: 3),
  AppGridColumn(label: AppStrings.ctLabelId, flex: 4),
  AppGridColumn(label: AppStrings.ctLabelStatus, flex: 2),
  AppGridColumn(label: AppStrings.ctLabelScope, flex: 2),
  AppGridColumn(
    label: AppStrings.ctLabelCreatedAt,
    flex: 3,
    alignment: Alignment.center,
  ),
  AppGridColumn(
    label: AppStrings.ctGridColumnActions,
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

  String _buildScopeLabel(ClientTokenSummary token) {
    if (token.allPermissions) return AppStrings.ctScopeAllPermissions;
    final scopes = <String>[
      if (token.allTables) AppStrings.ctScopeTables,
      if (token.allViews) AppStrings.ctScopeViews,
    ];
    return scopes.isEmpty ? AppStrings.ctScopeRestricted : scopes.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AppDataGridScrollable<ClientTokenSummary>(
      columns: _tokenGridColumns,
      rows: tokens,
      scrollController: scrollController,
      rowCells: (token) => [
        SelectableText(token.clientId),
        SelectableText(token.id),
        Text(
          token.isRevoked ? AppStrings.ctStatusRevoked : AppStrings.ctStatusActive,
        ),
        Text(_buildScopeLabel(token)),
        Text(
          DateFormat('dd/MM/yyyy HH:mm').format(token.createdAt.toLocal()),
        ),
        _TokenRowActions(
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
    required this.token,
    required this.isRevoking,
    required this.isDeleting,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onDelete,
    this.onRevoke,
  });

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
    final revokeTooltip = token.isRevoked ? AppStrings.ctButtonRevoked : AppStrings.ctButtonRevoke;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Tooltip(
          message: AppStrings.ctTooltipEditToken,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonEdit,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: onEdit,
            ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctButtonViewDetails,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonViewDetails,
            child: IconButton(
              icon: const Icon(FluentIcons.view),
              onPressed: onViewDetails,
            ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctTooltipCopyClientToken,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonCopyClientToken,
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
          message: AppStrings.ctButtonDelete,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonDelete,
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
