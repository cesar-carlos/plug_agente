import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

const _ruleDialogWidth = 620.0;
const _ruleDialogCompactBreakpoint = 760.0;
const _barrierOpacity = 0.4;

Future<ClientTokenRuleDraft?> showClientTokenRuleDialog({
  required BuildContext context,
  ClientTokenRuleDraft? initialRule,
}) {
  return showGeneralDialog<ClientTokenRuleDraft>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss rule dialog',
    barrierColor: Colors.black.withValues(alpha: _barrierOpacity),
    transitionDuration: AppConstants.ruleDialogTransition,
    pageBuilder: (dialogContext, primaryAnimation, secondaryAnimation) {
      return _ClientTokenRuleOverlay(initialRule: initialRule);
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: child,
      );
    },
  );
}

class _ClientTokenRuleOverlay extends StatefulWidget {
  const _ClientTokenRuleOverlay({this.initialRule});

  final ClientTokenRuleDraft? initialRule;

  @override
  State<_ClientTokenRuleOverlay> createState() => _ClientTokenRuleOverlayState();
}

class _ClientTokenRuleOverlayState extends State<_ClientTokenRuleOverlay> {
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
    final l10n = AppLocalizations.of(context)!;
    final resource = _resourceController.text.trim();
    if (resource.isEmpty) {
      setState(() => _formError = l10n.ctErrorRuleResourceRequired);
      return;
    }
    if (!(_canRead || _canUpdate || _canDelete)) {
      setState(() => _formError = l10n.ctErrorRulePermissionRequired);
      return;
    }
    final draft = ClientTokenRuleDraft(
      resource: resource,
      resourceType: _resourceType,
      effect: _effect,
      canRead: _canRead,
      canUpdate: _canUpdate,
      canDelete: _canDelete,
    );
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = FluentTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth > _ruleDialogCompactBreakpoint ? _ruleDialogWidth : screenWidth * 0.9;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          minWidth: dialogWidth,
        ),
        child: Card(
          padding: const EdgeInsets.all(AppSpacing.lg),
          backgroundColor: theme.resources.solidBackgroundFillColorBase,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? l10n.ctDialogEditRuleTitle : l10n.ctDialogAddRuleTitle,
                style: context.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<DatabaseResourceType>(
                      label: l10n.ctRuleFieldType,
                      value: _resourceType,
                      items: DatabaseResourceType.values
                          .where(
                            (item) => item != DatabaseResourceType.unknown,
                          )
                          .map(
                            (item) => ComboBoxItem<DatabaseResourceType>(
                              value: item,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _resourceType = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppDropdown<ClientTokenRuleEffect>(
                      label: l10n.ctRuleFieldEffect,
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
                        if (value != null) {
                          setState(() => _effect = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: l10n.ctRuleFieldResource,
                controller: _resourceController,
                hint: l10n.ctRuleHintResource,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _PermissionToggle(
                    label: l10n.ctPermissionRead,
                    value: _canRead,
                    onChanged: (v) => setState(() => _canRead = v),
                  ),
                  _PermissionToggle(
                    label: l10n.ctPermissionUpdate,
                    value: _canUpdate,
                    onChanged: (v) => setState(() => _canUpdate = v),
                  ),
                  _PermissionToggle(
                    label: l10n.ctPermissionDelete,
                    value: _canDelete,
                    onChanged: (v) => setState(() => _canDelete = v),
                  ),
                ],
              ),
              if (_formError.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                InlineFeedbackCard(
                  severity: InfoBarSeverity.error,
                  message: _formError,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: l10n.btnCancel,
                    isPrimary: false,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton(
                    label: l10n.ctDialogSaveRule,
                    onPressed: _handleSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
