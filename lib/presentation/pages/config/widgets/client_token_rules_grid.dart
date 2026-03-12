import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

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
    final strokeColor = FluentTheme.of(context).resources.controlStrokeColorDefault;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: strokeColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          _GridHeader(strokeColor: strokeColor),
          ...List<Widget>.generate(
            rules.length,
            (index) => _GridRow(
              rule: rules[index],
              index: index,
              strokeColor: strokeColor,
              onEdit: () => onEdit(index),
              onDelete: () => onDelete(index),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({required this.strokeColor});

  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: strokeColor)),
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text(AppStrings.ctGridColumnType)),
          Expanded(flex: 4, child: Text(AppStrings.ctGridColumnResource)),
          Expanded(flex: 2, child: Text(AppStrings.ctGridColumnEffect)),
          Expanded(flex: 4, child: Text(AppStrings.ctGridColumnPermissions)),
          Expanded(flex: 2, child: Text(AppStrings.ctGridColumnActions)),
        ],
      ),
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.rule,
    required this.index,
    required this.strokeColor,
    required this.onEdit,
    required this.onDelete,
  });

  final ClientTokenRuleDraft rule;
  final int index;
  final Color strokeColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final rowColor = index.isEven
        ? Colors.transparent
        : FluentTheme.of(context).resources.subtleFillColorSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          bottom: BorderSide(
            color: strokeColor.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(rule.resourceType.name)),
          Expanded(flex: 4, child: SelectableText(rule.resource)),
          Expanded(flex: 2, child: Text(rule.effect.name)),
          Expanded(flex: 4, child: Text(rule.permissionsLabel)),
          Expanded(
            flex: 2,
            child: Row(
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
          ),
        ],
      ),
    );
  }
}
