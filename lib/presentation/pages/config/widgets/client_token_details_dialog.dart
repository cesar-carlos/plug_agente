import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

Future<void> showClientTokenDetailsDialog({
  required BuildContext context,
  required ClientTokenSummary token,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _ClientTokenDetailsDialog(token: token),
  );
}

class _ClientTokenDetailsDialog extends StatelessWidget {
  const _ClientTokenDetailsDialog({required this.token});

  final ClientTokenSummary token;

  String _buildScopeLabel(AppLocalizations l10n) {
    if (token.allPermissions) {
      return l10n.ctScopeAllPermissions;
    }
    final scopes = <String>[];
    if (token.allTables) {
      scopes.add(l10n.ctScopeTables);
    }
    if (token.allViews) {
      scopes.add(l10n.ctScopeViews);
    }
    if (scopes.isEmpty) {
      return l10n.ctScopeRestricted;
    }
    return '${l10n.ctScopeRestricted} (${scopes.join(', ')})';
  }

  String _buildPayloadLabel() {
    if (token.payload.isEmpty) {
      return '{}';
    }
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(token.payload);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth > 980 ? 820.0 : screenWidth * 0.92;

    return ContentDialog(
      constraints: BoxConstraints(
        minWidth: dialogWidth,
        maxWidth: dialogWidth,
      ),
      title: Text(l10n.ctDialogTokenDetailsTitle),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailField(
                label: l10n.ctLabelClient,
                value: token.clientId,
                selectable: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailField(
                label: l10n.ctLabelId,
                value: token.id,
                selectable: true,
              ),
              if (token.agentId != null && token.agentId!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _DetailField(
                  label: l10n.ctLabelAgent,
                  value: token.agentId!,
                  selectable: true,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _DetailField(
                label: l10n.ctLabelStatus,
                value: token.isRevoked ? l10n.ctStatusRevoked : l10n.ctStatusActive,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailField(
                label: l10n.ctLabelScope,
                value: _buildScopeLabel(l10n),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailField(
                label: l10n.ctLabelCreatedAt,
                value: token.createdAt.toLocal().toIso8601String(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${l10n.ctLabelPayload}:',
                style: context.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              _CodeSurface(text: _buildPayloadLabel()),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${l10n.ctLabelRules}:',
                style: context.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              _RulesSurface(l10n: l10n, rules: token.rules),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.btnOk,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            '$label:',
            style: context.bodyStrong,
          ),
        ),
        Expanded(
          child: selectable ? SelectableText(value) : Text(value),
        ),
      ],
    );
  }
}

class _CodeSurface extends StatelessWidget {
  const _CodeSurface({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SelectableText(text),
    );
  }
}

class _RulesSurface extends StatelessWidget {
  const _RulesSurface({required this.l10n, required this.rules});

  final AppLocalizations l10n;
  final List<ClientTokenRule> rules;

  String _buildPermissionsLabel(ClientPermissionSet permissions) {
    final labels = <String>[];
    if (permissions.canRead) {
      labels.add(l10n.ctPermissionRead);
    }
    if (permissions.canUpdate) {
      labels.add(l10n.ctPermissionUpdate);
    }
    if (permissions.canDelete) {
      labels.add(l10n.ctPermissionDelete);
    }
    if (labels.isEmpty) {
      return l10n.ctRuleNoPermission;
    }
    return labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return Text(l10n.ctScopeNotInformed);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: List<Widget>.generate(
          rules.length,
          (index) => _RuleTile(
            l10n: l10n,
            rule: rules[index],
            permissionsLabel: _buildPermissionsLabel(rules[index].permissions),
            isLast: index == rules.length - 1,
          ),
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.l10n,
    required this.rule,
    required this.permissionsLabel,
    required this.isLast,
  });

  final AppLocalizations l10n;
  final ClientTokenRule rule;
  final String permissionsLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final strokeColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: strokeColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rule.resource.resourceType.name}: ${rule.resource.name}',
            style: context.bodyStrong,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('${l10n.ctRuleFieldEffectColon} ${rule.effect.name}'),
          const SizedBox(height: AppSpacing.xs),
          Text('${l10n.ctGridColumnPermissions}: $permissionsLabel'),
        ],
      ),
    );
  }
}
