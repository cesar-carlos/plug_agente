import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_policy_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_rules_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_form_shared.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class ClientTokenCreateDialogContent extends StatelessWidget {
  const ClientTokenCreateDialogContent({
    required this.isCompact,
    required this.isEditingToken,
    required this.policyChanged,
    required this.hasFormChanges,
    required this.agentFocusNode,
    required this.nameController,
    required this.clientIdController,
    required this.agentIdController,
    required this.payloadController,
    required this.rules,
    required this.allTables,
    required this.allViews,
    required this.globalCanRead,
    required this.globalCanUpdate,
    required this.globalCanDelete,
    required this.globalCanDdl,
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onToggleAllTables,
    required this.onToggleAllViews,
    required this.onToggleGlobalRead,
    required this.onToggleGlobalUpdate,
    required this.onToggleGlobalDelete,
    required this.onToggleGlobalDdl,
    required this.onAddRule,
    required this.onExportRules,
    required this.onImportRules,
    required this.isImportingRules,
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onDismissCreatedToken,
    required this.onFieldSubmitted,
    super.key,
  });

  final bool isCompact;
  final bool isEditingToken;
  final bool policyChanged;
  final bool hasFormChanges;
  final FocusNode agentFocusNode;
  final TextEditingController nameController;
  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final TextEditingController payloadController;
  final List<ClientTokenRuleDraft> rules;
  final bool allTables;
  final bool allViews;
  final bool globalCanRead;
  final bool globalCanUpdate;
  final bool globalCanDelete;
  final bool globalCanDdl;
  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final ValueChanged<bool> onToggleAllTables;
  final ValueChanged<bool> onToggleAllViews;
  final ValueChanged<bool> onToggleGlobalRead;
  final ValueChanged<bool> onToggleGlobalUpdate;
  final ValueChanged<bool> onToggleGlobalDelete;
  final ValueChanged<bool> onToggleGlobalDdl;
  final VoidCallback onAddRule;
  final VoidCallback onExportRules;
  final VoidCallback onImportRules;
  final bool isImportingRules;
  final ValueChanged<int> onEditRule;
  final ValueChanged<int> onDeleteRule;
  final VoidCallback onDismissCreatedToken;
  final VoidCallback onFieldSubmitted;

  bool get _isGlobalScopeMode => allTables || allViews;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ClientTokenFormErrorAnnouncer(
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
            ClientTokenIdentityFields(
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
            ClientTokenCreateDialogPolicySection(
              allTables: allTables,
              allViews: allViews,
              globalCanRead: globalCanRead,
              globalCanUpdate: globalCanUpdate,
              globalCanDelete: globalCanDelete,
              globalCanDdl: globalCanDdl,
              onToggleAllTables: onToggleAllTables,
              onToggleAllViews: onToggleAllViews,
              onToggleGlobalRead: onToggleGlobalRead,
              onToggleGlobalUpdate: onToggleGlobalUpdate,
              onToggleGlobalDelete: onToggleGlobalDelete,
              onToggleGlobalDdl: onToggleGlobalDdl,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isEditingToken) ...[
              ClientTokenEditDialogPolicyHint(
                policyChanged: policyChanged,
                hasFormChanges: hasFormChanges,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            ClientTokenCreateDialogRulesSection(
              rules: rules,
              isGlobalScopeMode: _isGlobalScopeMode,
              isImportingRules: isImportingRules,
              onAddRule: onAddRule,
              onExportRules: onExportRules,
              onImportRules: onImportRules,
              onEditRule: onEditRule,
              onDeleteRule: onDeleteRule,
            ),
            ClientTokenFeedbackPanel(
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
