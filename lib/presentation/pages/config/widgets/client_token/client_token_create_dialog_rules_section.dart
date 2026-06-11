import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class ClientTokenCreateDialogRulesSection extends StatelessWidget {
  const ClientTokenCreateDialogRulesSection({
    required this.rules,
    required this.isGlobalScopeMode,
    required this.isImportingRules,
    required this.onAddRule,
    required this.onExportRules,
    required this.onImportRules,
    required this.onEditRule,
    required this.onDeleteRule,
    super.key,
  });

  final List<ClientTokenRuleDraft> rules;
  final bool isGlobalScopeMode;
  final bool isImportingRules;
  final VoidCallback onAddRule;
  final VoidCallback onExportRules;
  final VoidCallback onImportRules;
  final ValueChanged<int> onEditRule;
  final ValueChanged<int> onDeleteRule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SettingsSectionTitle(
                title: l10n.ctSectionRulesByResource,
              ),
            ),
            Flexible(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  if (!isGlobalScopeMode)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(20),
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
                              onPressed: onImportRules,
                            ),
                    ),
                  if (!isGlobalScopeMode && rules.isNotEmpty)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(21),
                      child: AppButton(
                        label: l10n.ctButtonExportRules,
                        isPrimary: false,
                        icon: FluentIcons.download,
                        onPressed: onExportRules,
                      ),
                    ),
                  if (!isGlobalScopeMode)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(22),
                      child: AppButton(
                        label: l10n.ctButtonAddRule,
                        isPrimary: false,
                        icon: FluentIcons.add,
                        onPressed: onAddRule,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (isGlobalScopeMode)
          Text(l10n.ctGlobalScopeRulesDisabled)
        else if (rules.isEmpty)
          Text(l10n.ctNoRulesAdded)
        else
          ClientTokenRulesGrid(
            rules: rules,
            onEdit: onEditRule,
            onDelete: onDeleteRule,
          ),
      ],
    );
  }
}
