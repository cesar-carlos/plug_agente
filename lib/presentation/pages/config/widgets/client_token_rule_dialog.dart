import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

Future<ClientTokenRuleDraft?> showClientTokenRuleDialog({
  required BuildContext context,
  ClientTokenRuleDraft? initialRule,
}) {
  return showDialog<ClientTokenRuleDraft>(
    context: context,
    builder: (context) => _ClientTokenRuleDialog(initialRule: initialRule),
  );
}

class _ClientTokenRuleDialog extends StatefulWidget {
  const _ClientTokenRuleDialog({this.initialRule});

  final ClientTokenRuleDraft? initialRule;

  @override
  State<_ClientTokenRuleDialog> createState() => _ClientTokenRuleDialogState();
}

class _ClientTokenRuleDialogState extends State<_ClientTokenRuleDialog> {
  late final TextEditingController _resourceController;
  late DatabaseResourceType _resourceType;
  late ClientTokenRuleEffect _effect;
  late bool _canRead;
  late bool _canUpdate;
  late bool _canDelete;
  String _formError = '';

  bool get _isEditing => widget.initialRule != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRule;
    _resourceController = TextEditingController(text: initial?.resource ?? '');
    _resourceType = initial?.resourceType ?? DatabaseResourceType.table;
    _effect = initial?.effect ?? ClientTokenRuleEffect.allow;
    _canRead = initial?.canRead ?? true;
    _canUpdate = initial?.canUpdate ?? false;
    _canDelete = initial?.canDelete ?? false;
  }

  @override
  void dispose() {
    _resourceController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final resource = _resourceController.text.trim();
    if (resource.isEmpty) {
      setState(() {
        _formError = AppStrings.ctErrorRuleResourceRequired;
      });
      return;
    }

    if (!(_canRead || _canUpdate || _canDelete)) {
      setState(() {
        _formError = AppStrings.ctErrorRulePermissionRequired;
      });
      return;
    }

    Navigator.of(context, rootNavigator: true).pop(
      ClientTokenRuleDraft(
        resource: resource,
        resourceType: _resourceType,
        effect: _effect,
        canRead: _canRead,
        canUpdate: _canUpdate,
        canDelete: _canDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth > 760 ? 620.0 : screenWidth * 0.9;

    return ContentDialog(
      constraints: BoxConstraints(
        minWidth: dialogWidth,
        maxWidth: dialogWidth,
      ),
      title: Text(
        _isEditing
            ? AppStrings.ctDialogEditRuleTitle
            : AppStrings.ctDialogAddRuleTitle,
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDropdown<DatabaseResourceType>(
                    label: AppStrings.ctRuleFieldType,
                    value: _resourceType,
                    items: DatabaseResourceType.values
                        .where((item) => item != DatabaseResourceType.unknown)
                        .map(
                          (item) => ComboBoxItem<DatabaseResourceType>(
                            value: item,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _resourceType = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDropdown<ClientTokenRuleEffect>(
                    label: AppStrings.ctRuleFieldEffect,
                    value: _effect,
                    items: ClientTokenRuleEffect.values
                        .map(
                          (item) => ComboBoxItem<ClientTokenRuleEffect>(
                            value: item,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _effect = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: AppStrings.ctRuleFieldResource,
              controller: _resourceController,
              hint: AppStrings.ctRuleHintResource,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _PermissionToggle(
                  label: AppStrings.ctPermissionRead,
                  value: _canRead,
                  onChanged: (value) {
                    setState(() {
                      _canRead = value;
                    });
                  },
                ),
                _PermissionToggle(
                  label: AppStrings.ctPermissionUpdate,
                  value: _canUpdate,
                  onChanged: (value) {
                    setState(() {
                      _canUpdate = value;
                    });
                  },
                ),
                _PermissionToggle(
                  label: AppStrings.ctPermissionDelete,
                  value: _canDelete,
                  onChanged: (value) {
                    setState(() {
                      _canDelete = value;
                    });
                  },
                ),
              ],
            ),
            if (_formError.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _formError,
                style: TextStyle(
                  color: Colors.red.normal,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text(AppStrings.btnCancel),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: const Text(AppStrings.ctDialogSaveRule),
        ),
      ],
    );
  }
}

class _PermissionToggle extends StatelessWidget {
  const _PermissionToggle({
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
