import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/password_field.dart';
import 'package:result_dart/result_dart.dart';

Future<bool> showAgentActionSecretConfigureDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  required String secretName,
  required Future<Result<Unit>> Function(String secretValue) onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  final valueController = TextEditingController();
  var isSaving = false;
  String? errorMessage;

  final saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          return ContentDialog(
            title: Text(l10n.agentActionsSecretConfigureTitle(secretName)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.agentActionsSecretConfigureMessage),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: valueController,
                    label: l10n.agentActionsSecretConfigureValueLabel,
                    hint: l10n.agentActionsSecretConfigureValueHint,
                    enabled: !isSaving,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    InfoBar(
                      title: Text(l10n.agentActionsSecretConfigureErrorTitle),
                      content: SelectableText(errorMessage!),
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
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext, false),
                child: Text(l10n.agentActionsSecretConfigureCancel),
              ),
              FilledButton(
                key: const ValueKey<String>('agent_action_secret_dialog_save_button'),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }

                        setState(() {
                          isSaving = true;
                          errorMessage = null;
                        });

                        final result = await onSave(valueController.text);
                        if (!dialogContext.mounted) {
                          return;
                        }

                        result.fold(
                          (_) => Navigator.pop(dialogContext, true),
                          (failure) {
                            setState(() {
                              isSaving = false;
                              errorMessage = failure is ActionFailure
                                  ? ((failure.context['user_message'] as String?)?.trim().isNotEmpty ?? false)
                                        ? failure.context['user_message']! as String
                                        : failure.message
                                  : failure.toString();
                            });
                          },
                        );
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : Text(l10n.agentActionsSecretConfigureSave),
              ),
            ],
          );
        },
      );
    },
  );

  valueController.dispose();
  return saved ?? false;
}

Future<bool> confirmDeleteAgentActionSecret({
  required BuildContext context,
  required AppLocalizations l10n,
  required String secretName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return ContentDialog(
        title: Text(l10n.agentActionsSecretDeleteTitle),
        content: Text(l10n.agentActionsSecretDeleteMessage(secretName)),
        actions: [
          Button(
            key: const ValueKey<String>('agent_action_secret_delete_cancel_button'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.agentActionsSecretDeleteCancel),
          ),
          FilledButton(
            key: const ValueKey<String>('agent_action_secret_delete_confirm_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.agentActionsSecretDeleteConfirm),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
