import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class ClientTokenRuleRow extends StatelessWidget {
  const ClientTokenRuleRow({
    required this.title,
    required this.resourceController,
    required this.resourceType,
    required this.effect,
    required this.canRead,
    required this.canUpdate,
    required this.canDelete,
    required this.onResourceTypeChanged,
    required this.onEffectChanged,
    required this.onReadChanged,
    required this.onUpdateChanged,
    required this.onDeleteChanged,
    required this.onRemove,
    super.key,
  });

  final String title;
  final TextEditingController resourceController;
  final DatabaseResourceType resourceType;
  final ClientTokenRuleEffect effect;
  final bool canRead;
  final bool canUpdate;
  final bool canDelete;
  final ValueChanged<DatabaseResourceType> onResourceTypeChanged;
  final ValueChanged<ClientTokenRuleEffect> onEffectChanged;
  final ValueChanged<bool> onReadChanged;
  final ValueChanged<bool> onUpdateChanged;
  final ValueChanged<bool> onDeleteChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: context.bodyStrong),
              ),
              IconButton(
                icon: const Icon(FluentIcons.delete),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppDropdown<DatabaseResourceType>(
                  label: 'Tipo',
                  value: resourceType,
                  items: DatabaseResourceType.values
                      .where((type) => type != DatabaseResourceType.unknown)
                      .map(
                        (type) => ComboBoxItem<DatabaseResourceType>(
                          value: type,
                          child: Text(type.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onResourceTypeChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdown<ClientTokenRuleEffect>(
                  label: 'Efeito',
                  value: effect,
                  items: ClientTokenRuleEffect.values
                      .map(
                        (item) => ComboBoxItem<ClientTokenRuleEffect>(
                          value: item,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onEffectChanged(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Recurso (schema.nome)',
            controller: resourceController,
            hint: 'dbo.clientes',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _PermissionCheckbox(
                label: 'Read',
                value: canRead,
                onChanged: onReadChanged,
              ),
              _PermissionCheckbox(
                label: 'Update',
                value: canUpdate,
                onChanged: onUpdateChanged,
              ),
              _PermissionCheckbox(
                label: 'Delete',
                value: canDelete,
                onChanged: onDeleteChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionCheckbox extends StatelessWidget {
  const _PermissionCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      checked: value,
      onChanged: (isChecked) => onChanged(isChecked ?? false),
      content: Text(label),
    );
  }
}
