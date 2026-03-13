import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/shared/widgets/common/layout_components.dart';

class ClientTokenRuleDraft {
  const ClientTokenRuleDraft({
    required this.resource,
    required this.resourceType,
    required this.effect,
    required this.canRead,
    required this.canUpdate,
    required this.canDelete,
  });

  final String resource;
  final DatabaseResourceType resourceType;
  final ClientTokenRuleEffect effect;
  final bool canRead;
  final bool canUpdate;
  final bool canDelete;

  bool get hasAnyPermission => canRead || canUpdate || canDelete;

  String get permissionsLabel {
    final labels = <String>[];
    if (canRead) labels.add(AppStrings.ctPermissionRead);
    if (canUpdate) labels.add(AppStrings.ctPermissionUpdate);
    if (canDelete) labels.add(AppStrings.ctPermissionDelete);
    return labels.join(', ');
  }

  ClientTokenRuleDraft copyWith({
    String? resource,
    DatabaseResourceType? resourceType,
    ClientTokenRuleEffect? effect,
    bool? canRead,
    bool? canUpdate,
    bool? canDelete,
  }) {
    return ClientTokenRuleDraft(
      resource: resource ?? this.resource,
      resourceType: resourceType ?? this.resourceType,
      effect: effect ?? this.effect,
      canRead: canRead ?? this.canRead,
      canUpdate: canUpdate ?? this.canUpdate,
      canDelete: canDelete ?? this.canDelete,
    );
  }
}

const _columns = [
  AppGridColumn(label: AppStrings.ctGridColumnType, flex: 2),
  AppGridColumn(label: AppStrings.ctGridColumnResource, flex: 4),
  AppGridColumn(label: AppStrings.ctGridColumnEffect, flex: 2),
  AppGridColumn(label: AppStrings.ctGridColumnPermissions, flex: 4),
  AppGridColumn(label: AppStrings.ctGridColumnActions, flex: 2),
];

const _compactGridBreakpoint = 900.0;

class ClientTokenRulesGrid extends StatelessWidget {
  const ClientTokenRulesGrid({
    required this.rules,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final List<ClientTokenRuleDraft> rules;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.hasBoundedWidth &&
            constraints.maxWidth < _compactGridBreakpoint;

        if (isCompact) {
          return Column(
            children: List<Widget>.generate(
              rules.length,
              (index) => Padding(
                padding: EdgeInsets.only(
                  bottom: index == rules.length - 1 ? 0 : AppSpacing.sm,
                ),
                child: _CompactRuleCard(
                  rule: rules[index],
                  onEdit: () => onEdit(index),
                  onDelete: () => onDelete(index),
                ),
              ),
            ),
          );
        }

        return AppDataGrid<ClientTokenRuleDraft>(
          columns: _columns,
          rows: rules,
          rowCells: (rule) => [
            Text(rule.resourceType.name),
            SelectableText(rule.resource),
            Text(rule.effect.name),
            Text(rule.permissionsLabel),
            _RuleActions(
              onEdit: () => onEdit(rules.indexOf(rule)),
              onDelete: () => onDelete(rules.indexOf(rule)),
            ),
          ],
        );
      },
    );
  }
}

class _RuleActions extends StatelessWidget {
  const _RuleActions({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: AppStrings.ctTooltipEditRule,
          child: Semantics(
            button: true,
            label: AppStrings.ctTooltipEditRule,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: onEdit,
            ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctTooltipDeleteRule,
          child: Semantics(
            button: true,
            label: AppStrings.ctTooltipDeleteRule,
            child: IconButton(
              icon: const Icon(FluentIcons.delete),
              onPressed: onDelete,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactRuleCard extends StatelessWidget {
  const _CompactRuleCard({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final ClientTokenRuleDraft rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strokeColor =
        FluentTheme.of(context).resources.controlStrokeColorDefault;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: strokeColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompactValueRow(
            label: AppStrings.ctGridColumnType,
            value: rule.resourceType.name,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: AppStrings.ctGridColumnResource,
            value: rule.resource,
            isSelectable: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: AppStrings.ctGridColumnEffect,
            value: rule.effect.name,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: AppStrings.ctGridColumnPermissions,
            value: rule.permissionsLabel,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Tooltip(
                message: AppStrings.ctTooltipEditRule,
                child: Semantics(
                  button: true,
                  label: AppStrings.ctTooltipEditRule,
                  child: IconButton(
                    icon: const Icon(FluentIcons.edit),
                    onPressed: onEdit,
                  ),
                ),
              ),
              Tooltip(
                message: AppStrings.ctTooltipDeleteRule,
                child: Semantics(
                  button: true,
                  label: AppStrings.ctTooltipDeleteRule,
                  child: IconButton(
                    icon: const Icon(FluentIcons.delete),
                    onPressed: onDelete,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactValueRow extends StatelessWidget {
  const _CompactValueRow({
    required this.label,
    required this.value,
    this.isSelectable = false,
  });

  final String label;
  final String value;
  final bool isSelectable;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (isSelectable)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SelectableText(value),
            )
          else
            TextSpan(text: value),
        ],
      ),
    );
  }
}
