import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_confirm_dialog.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_dialog_title_bar.dart';
import 'package:plug_agente/shared/widgets/common/form/password_field.dart';
import 'package:result_dart/result_dart.dart';

Future<bool> showAgentActionSecretConfigureDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  required String secretName,
  required Future<Result<Unit>> Function(String secretValue) onSave,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _AgentActionSecretConfigureDialog(
        l10n: l10n,
        secretName: secretName,
        onSave: onSave,
      );
    },
  );

  return saved ?? false;
}

class _AgentActionSecretConfigureDialog extends StatefulWidget {
  const _AgentActionSecretConfigureDialog({
    required this.l10n,
    required this.secretName,
    required this.onSave,
  });

  final AppLocalizations l10n;
  final String secretName;
  final Future<Result<Unit>> Function(String secretValue) onSave;

  @override
  State<_AgentActionSecretConfigureDialog> createState() => _AgentActionSecretConfigureDialogState();
}

class _AgentActionSecretConfigureDialogState extends State<_AgentActionSecretConfigureDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _valueController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: AppDialogTitleBar(
        title: Text(widget.l10n.agentActionsSecretConfigureTitle(widget.secretName)),
        closeTooltip: widget.l10n.btnClose,
        canClose: !_isSaving,
        onClose: () => Navigator.pop(context, false),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.l10n.agentActionsSecretConfigureMessage),
            const SizedBox(height: 12),
            PasswordField(
              controller: _valueController,
              label: widget.l10n.agentActionsSecretConfigureValueLabel,
              hint: widget.l10n.agentActionsSecretConfigureValueHint,
              enabled: !_isSaving,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              InfoBar(
                title: Text(widget.l10n.agentActionsSecretConfigureErrorTitle),
                content: SelectableText(_errorMessage!),
                severity: InfoBarSeverity.error,
                isLong: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          key: const ValueKey<String>('agent_action_secret_dialog_cancel_button'),
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: Text(widget.l10n.agentActionsSecretConfigureCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('agent_action_secret_dialog_save_button'),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
              : Text(widget.l10n.agentActionsSecretConfigureSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await widget.onSave(_valueController.text);
    if (!mounted) {
      return;
    }

    result.fold(
      (_) => Navigator.pop(context, true),
      (failure) {
        final userMessage = failure is ActionFailure
            ? ((failure.context['user_message'] as String?)?.trim().isNotEmpty ?? false)
                  ? failure.context['user_message']! as String
                  : failure.message
            : failure is domain_failures.Failure
            ? failure.message
            : failure.toString();
        setState(() {
          _isSaving = false;
          _errorMessage = userMessage;
        });
      },
    );
  }
}

Future<bool> confirmDeleteAgentActionSecret({
  required BuildContext context,
  required AppLocalizations l10n,
  required String secretName,
}) {
  return AppConfirmDialog.show(
    context: context,
    title: l10n.agentActionsSecretDeleteTitle,
    message: l10n.agentActionsSecretDeleteMessage(secretName),
    confirmLabel: l10n.agentActionsSecretDeleteConfirm,
    cancelLabel: l10n.agentActionsSecretDeleteCancel,
  );
}
