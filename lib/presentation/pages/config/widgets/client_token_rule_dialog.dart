import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_form_shared.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_rule_parser.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

export 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_rule_parser.dart'
    show TokenRuleImportLineError, TokenRuleImportResult, maxRuleImportFileSizeBytes, parseTokenRulesStrict;

const _ruleDialogWidth = 620.0;
const _ruleDialogCompactBreakpoint = 760.0;
const _barrierOpacity = 0.4;

/// Returns a list of [ClientTokenRuleDraft] when the user saves, or null when
/// the dialog is dismissed. When editing an existing rule, the list always
/// contains exactly one element.
///
/// [existingRules] is used to detect duplicates. On manual entry the dialog
/// will ask for confirmation before overwriting. File imports overwrite silently.
Future<List<ClientTokenRuleDraft>?> showClientTokenRuleDialog({
  required BuildContext context,
  ClientTokenRuleDraft? initialRule,
  List<ClientTokenRuleDraft> existingRules = const [],
}) {
  final l10n = AppLocalizations.of(context)!;
  return showGeneralDialog<List<ClientTokenRuleDraft>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.ctDialogDismissRule,
    barrierColor: Colors.black.withValues(alpha: _barrierOpacity),
    transitionDuration: AppConstants.ruleDialogTransition,
    pageBuilder: (dialogContext, primaryAnimation, secondaryAnimation) {
      return _ClientTokenRuleOverlay(
        initialRule: initialRule,
        existingRules: existingRules,
      );
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
  const _ClientTokenRuleOverlay({
    this.initialRule,
    this.existingRules = const [],
  });

  final ClientTokenRuleDraft? initialRule;
  final List<ClientTokenRuleDraft> existingRules;

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
  late bool _canDdl;
  String _formError = '';
  String _duplicateWarning = '';
  List<ClientTokenRuleDraft>? _pendingDrafts;
  bool _isLoadingFile = false;

  bool get _isEditing => widget.initialRule != null;

  List<String> _findDuplicates(List<ClientTokenRuleDraft> drafts) {
    return drafts
        .where(
          (d) => widget.existingRules.any((e) {
            if (_isEditing &&
                e.resource.toLowerCase() == widget.initialRule!.resource.toLowerCase() &&
                e.resourceType == widget.initialRule!.resourceType) {
              return false;
            }
            return e.resource.toLowerCase() == d.resource.toLowerCase() && e.resourceType == d.resourceType;
          }),
        )
        .map((d) => d.resource)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRule;
    _resourceController = TextEditingController(text: initial?.resource ?? '');
    _resourceController.addListener(_clearPendingOnChange);
    _resourceType = initial?.resourceType ?? DatabaseResourceType.table;
    _effect = initial?.effect ?? ClientTokenRuleEffect.allow;
    _canRead = initial?.canRead ?? true;
    _canUpdate = initial?.canUpdate ?? false;
    _canDelete = initial?.canDelete ?? false;
    _canDdl = initial?.canDdl ?? false;
  }

  void _clearPendingOnChange() {
    if (_pendingDrafts != null) {
      setState(() {
        _pendingDrafts = null;
        _duplicateWarning = '';
      });
    }
  }

  void _onTypeChanged(DatabaseResourceType? value) {
    if (value == null) return;
    _clearPendingOnChange();
    setState(() => _resourceType = value);
  }

  void _onEffectChanged(ClientTokenRuleEffect? value) {
    if (value == null) return;
    _clearPendingOnChange();
    setState(() => _effect = value);
  }

  void _onPermissionChanged(void Function() setter) {
    _clearPendingOnChange();
    setState(setter);
  }

  @override
  void dispose() {
    _resourceController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final l10n = AppLocalizations.of(context)!;

    if (_pendingDrafts != null) {
      Navigator.of(context).pop(_pendingDrafts);
      return;
    }

    final rawText = _resourceController.text.trim();

    if (rawText.isEmpty) {
      setState(() => _formError = l10n.ctErrorRuleResourceRequired);
      return;
    }
    if (!(_canRead || _canUpdate || _canDelete || _canDdl)) {
      setState(() => _formError = l10n.ctErrorRulePermissionRequired);
      return;
    }

    final result = parseTokenRulesFlexible(
      rawText,
      defaultType: _resourceType,
      defaultEffect: _effect,
      defaultCanRead: _canRead,
      defaultCanUpdate: _canUpdate,
      defaultCanDelete: _canDelete,
      defaultCanDdl: _canDdl,
    );

    if (result.hasErrors) {
      final firstError = result.errors.first;
      setState(() {
        _formError = l10n.ctErrorRuleResourceInvalidChars(firstError.content);
        _duplicateWarning = '';
        _pendingDrafts = null;
      });
      return;
    }

    if (result.drafts.isEmpty) {
      setState(() => _formError = l10n.ctErrorRuleResourceRequired);
      return;
    }

    final duplicates = _findDuplicates(result.drafts);
    if (duplicates.isNotEmpty) {
      setState(() {
        _formError = '';
        _duplicateWarning = l10n.ctRuleWarnDuplicates(duplicates.join(', '));
        _pendingDrafts = result.drafts;
      });
      return;
    }

    Navigator.of(context).pop(result.drafts);
  }

  Future<void> _handleImportFile() async {
    final l10n = AppLocalizations.of(context)!;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
    } on Exception {
      if (mounted) setState(() => _formError = l10n.ctRuleImportErrorNoValidLines);
      return;
    }

    if (picked == null || picked.files.isEmpty) return;

    final filePath = picked.files.single.path;
    if (filePath == null) {
      if (mounted) setState(() => _formError = l10n.ctRuleImportErrorNoValidLines);
      return;
    }

    setState(() {
      _isLoadingFile = true;
      _formError = '';
      _duplicateWarning = '';
      _pendingDrafts = null;
    });

    try {
      final file = File(filePath);
      final size = await file.length();
      if (!mounted) return;
      if (size == 0) {
        setState(() => _formError = l10n.ctRuleImportErrorEmpty);
        return;
      }
      if (size > maxRuleImportFileSizeBytes) {
        setState(() => _formError = l10n.ctRuleImportErrorFileTooLarge);
        return;
      }

      final content = await file.readAsString();
      if (!mounted) return;

      final parseResult = parseTokenRulesFlexible(
        content,
        defaultType: _resourceType,
        defaultEffect: _effect,
        defaultCanRead: _canRead,
        defaultCanUpdate: _canUpdate,
        defaultCanDelete: _canDelete,
        defaultCanDdl: _canDdl,
      );

      if (parseResult.drafts.isEmpty) {
        setState(() => _formError = l10n.ctRuleImportErrorNoValidLines);
        return;
      }

      if (parseResult.hasErrors) {
        final firstError = parseResult.errors.first;
        setState(
          () => _formError = l10n.ctRuleImportErrorLineInvalid(
            firstError.line,
            firstError.content,
          ),
        );
        return;
      }

      Navigator.of(context).pop(parseResult.drafts);
    } on FormatException {
      if (mounted) setState(() => _formError = l10n.ctRuleImportErrorNoValidLines);
    } on Exception {
      if (mounted) setState(() => _formError = l10n.ctRuleImportErrorNoValidLines);
    } finally {
      if (mounted) setState(() => _isLoadingFile = false);
    }
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
                          .where((item) => item != DatabaseResourceType.unknown)
                          .map(
                            (item) => ComboBoxItem<DatabaseResourceType>(
                              value: item,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: _onTypeChanged,
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
                      onChanged: _onEffectChanged,
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
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isLoadingFile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : AppButton(
                          label: l10n.ctRuleImportFile,
                          isPrimary: false,
                          icon: FluentIcons.upload,
                          onPressed: _handleImportFile,
                        ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  ClientTokenPermissionToggle(
                    label: l10n.ctPermissionRead,
                    value: _canRead,
                    onChanged: (v) => _onPermissionChanged(() => _canRead = v),
                  ),
                  ClientTokenPermissionToggle(
                    label: l10n.ctPermissionUpdate,
                    value: _canUpdate,
                    onChanged: (v) => _onPermissionChanged(() => _canUpdate = v),
                  ),
                  ClientTokenPermissionToggle(
                    label: l10n.ctPermissionDelete,
                    value: _canDelete,
                    onChanged: (v) => _onPermissionChanged(() => _canDelete = v),
                  ),
                  ClientTokenPermissionToggle(
                    label: l10n.ctPermissionDdl,
                    value: _canDdl,
                    onChanged: (v) => _onPermissionChanged(() => _canDdl = v),
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
              if (_duplicateWarning.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                InlineFeedbackCard(
                  severity: InfoBarSeverity.warning,
                  message: _duplicateWarning,
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
                    label: _pendingDrafts != null ? l10n.ctDialogConfirmReplace : l10n.ctDialogSaveRule,
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
