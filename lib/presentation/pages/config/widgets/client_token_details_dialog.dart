import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
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

  String _buildScopeLabel() {
    if (token.allPermissions) {
      return AppStrings.ctScopeAllPermissions;
    }
    final scopes = <String>[];
    if (token.allTables) {
      scopes.add(AppStrings.ctScopeTables);
    }
    if (token.allViews) {
      scopes.add(AppStrings.ctScopeViews);
    }
    if (scopes.isEmpty) {
      return AppStrings.ctScopeRestricted;
    }
    return '${AppStrings.ctScopeRestricted} (${scopes.join(', ')})';
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth > 980 ? 820.0 : screenWidth * 0.92;

    return ContentDialog(
      constraints: BoxConstraints(
        minWidth: dialogWidth,
        maxWidth: dialogWidth,
      ),
      title: const Text(AppStrings.ctDialogTokenDetailsTitle),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailField(
              label: AppStrings.ctLabelClient,
              value: token.clientId,
              selectable: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _DetailField(
              label: AppStrings.ctLabelId,
              value: token.id,
              selectable: true,
            ),
            if (token.agentId != null && token.agentId!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _DetailField(
                label: AppStrings.ctLabelAgent,
                value: token.agentId!,
                selectable: true,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _DetailField(
              label: AppStrings.ctLabelStatus,
              value: token.isRevoked
                  ? AppStrings.ctStatusRevoked
                  : AppStrings.ctStatusActive,
            ),
            const SizedBox(height: AppSpacing.sm),
            _DetailField(
              label: AppStrings.ctLabelScope,
              value: _buildScopeLabel(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DetailField(
              label: AppStrings.ctLabelCreatedAt,
              value: token.createdAt.toLocal().toIso8601String(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${AppStrings.ctLabelPayload}:',
              style: context.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.xs),
            _CodeSurface(text: _buildPayloadLabel()),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${AppStrings.ctLabelRules}:',
              style: context.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.xs),
            _RulesSurface(rules: token.rules),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: AppStrings.btnOk,
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
  const _RulesSurface({required this.rules});

  final List<ClientTokenRule> rules;

  String _buildPermissionsLabel(ClientPermissionSet permissions) {
    final labels = <String>[];
    if (permissions.canRead) {
      labels.add(AppStrings.ctPermissionRead);
    }
    if (permissions.canUpdate) {
      labels.add(AppStrings.ctPermissionUpdate);
    }
    if (permissions.canDelete) {
      labels.add(AppStrings.ctPermissionDelete);
    }
    if (labels.isEmpty) {
      return AppStrings.ctRuleNoPermission;
    }
    return labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const Text(AppStrings.ctScopeNotInformed);
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
    required this.rule,
    required this.permissionsLabel,
    required this.isLast,
  });

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
          Text('${AppStrings.ctRuleFieldEffect}: ${rule.effect.name}'),
          const SizedBox(height: AppSpacing.xs),
          Text('${AppStrings.ctGridColumnPermissions}: $permissionsLabel'),
        ],
      ),
    );
  }
}
