import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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

  String permissionsLabel(AppLocalizations l10n) {
    final labels = <String>[];
    if (canRead) labels.add(l10n.ctPermissionRead);
    if (canUpdate) labels.add(l10n.ctPermissionUpdate);
    if (canDelete) labels.add(l10n.ctPermissionDelete);
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

List<AppGridColumn> _gridColumns(AppLocalizations l10n) => [
  AppGridColumn(label: l10n.ctGridColumnType, flex: 2),
  AppGridColumn(label: l10n.ctGridColumnResource, flex: 4),
  AppGridColumn(label: l10n.ctGridColumnEffect, flex: 2),
  AppGridColumn(label: l10n.ctGridColumnPermissions, flex: 4),
  AppGridColumn(label: l10n.ctGridColumnActions, flex: 2),
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
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.hasBoundedWidth && constraints.maxWidth < _compactGridBreakpoint;

        if (isCompact) {
          return Column(
            children: List<Widget>.generate(
              rules.length,
              (index) => Padding(
                padding: EdgeInsets.only(
                  bottom: index == rules.length - 1 ? 0 : AppSpacing.sm,
                ),
                child: _CompactRuleCard(
                  l10n: l10n,
                  rule: rules[index],
                  onEdit: () => onEdit(index),
                  onDelete: () => onDelete(index),
                ),
              ),
            ),
          );
        }

        return AppDataGrid<ClientTokenRuleDraft>(
          columns: _gridColumns(l10n),
          rows: rules,
          rowCells: (rule) {
            final index = rules.indexWhere((r) => identical(r, rule));
            return [
              Text(rule.resourceType.name),
              SelectableText(rule.resource),
              Text(rule.effect.name),
              Text(rule.permissionsLabel(l10n)),
              _RuleActions(
                l10n: l10n,
                onEdit: () => onEdit(index),
                onDelete: () => onDelete(index),
              ),
            ];
          },
        );
      },
    );
  }
}

class _RuleActions extends StatelessWidget {
  const _RuleActions({required this.l10n, required this.onEdit, required this.onDelete});

  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.ctTooltipEditRule,
          child: Semantics(
            button: true,
            label: l10n.ctTooltipEditRule,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: onEdit,
            ),
          ),
        ),
        Tooltip(
          message: l10n.ctTooltipDeleteRule,
          child: Semantics(
            button: true,
            label: l10n.ctTooltipDeleteRule,
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
    required this.l10n,
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  final AppLocalizations l10n;
  final ClientTokenRuleDraft rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strokeColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;
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
            label: l10n.ctGridColumnType,
            value: rule.resourceType.name,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: l10n.ctGridColumnResource,
            value: rule.resource,
            isSelectable: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: l10n.ctGridColumnEffect,
            value: rule.effect.name,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CompactValueRow(
            label: l10n.ctGridColumnPermissions,
            value: rule.permissionsLabel(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Tooltip(
                message: l10n.ctTooltipEditRule,
                child: Semantics(
                  button: true,
                  label: l10n.ctTooltipEditRule,
                  child: IconButton(
                    icon: const Icon(FluentIcons.edit),
                    onPressed: onEdit,
                  ),
                ),
              ),
              Tooltip(
                message: l10n.ctTooltipDeleteRule,
                child: Semantics(
                  button: true,
                  label: l10n.ctTooltipDeleteRule,
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
