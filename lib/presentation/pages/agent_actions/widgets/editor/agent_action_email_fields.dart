import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

/// Input fields for an email action draft.
class AgentActionEmailFields extends StatelessWidget {
  const AgentActionEmailFields({
    required this.l10n,
    required this.enabled,
    required this.smtpProfileIdController,
    required this.fromController,
    required this.toController,
    required this.ccController,
    required this.bccController,
    required this.subjectController,
    required this.bodyController,
    required this.attachmentsController,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController smtpProfileIdController;
  final TextEditingController fromController;
  final TextEditingController toController;
  final TextEditingController ccController;
  final TextEditingController bccController;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final TextEditingController attachmentsController;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormSmtpProfileId,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: smtpProfileIdController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormSmtpProfileIdHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailFrom,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: fromController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailTo,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: toController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailToHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailCc,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: ccController,
          enabled: enabled,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailCcHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailBcc,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: bccController,
          enabled: enabled,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailBccHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailSubject,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: subjectController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailSubjectHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailBody,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: bodyController,
          enabled: enabled,
          maxLines: 8,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailBodyHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailAttachments,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: attachmentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          hint: l10n.agentActionsFormEmailAttachmentsHint,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}
