import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class ClientTokenFormErrorAnnouncer extends StatefulWidget {
  const ClientTokenFormErrorAnnouncer({
    required this.formError,
    required this.providerError,
    required this.child,
    super.key,
  });

  final String formError;
  final String providerError;
  final Widget child;

  @override
  State<ClientTokenFormErrorAnnouncer> createState() => _ClientTokenFormErrorAnnouncerState();
}

class _ClientTokenFormErrorAnnouncerState extends State<ClientTokenFormErrorAnnouncer> {
  @override
  void didUpdateWidget(covariant ClientTokenFormErrorAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _announceIfNew(widget.formError, oldWidget.formError);
    _announceIfNew(widget.providerError, oldWidget.providerError);
  }

  void _announceIfNew(String next, String previous) {
    if (next.isEmpty || next == previous) {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      next,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ClientTokenEditDialogPolicyHint extends StatelessWidget {
  const ClientTokenEditDialogPolicyHint({
    required this.policyChanged,
    required this.hasFormChanges,
    super.key,
  });

  final bool policyChanged;
  final bool hasFormChanges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final InfoBarSeverity severity;
    final String message;
    if (policyChanged) {
      severity = InfoBarSeverity.warning;
      message = l10n.ctEditPolicyChangedHint;
    } else if (!hasFormChanges) {
      severity = InfoBarSeverity.info;
      message = l10n.ctEditNoChangesHint;
    } else {
      severity = InfoBarSeverity.info;
      message = l10n.ctEditMetadataOnlyHint;
    }
    return InlineFeedbackCard(
      severity: severity,
      message: message,
    );
  }
}

class ClientTokenIdentityFields extends StatelessWidget {
  const ClientTokenIdentityFields({
    required this.clientIdController,
    required this.agentIdController,
    required this.agentFocusNode,
    required this.isCompact,
    required this.onAgentSubmitted,
    super.key,
  });

  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final FocusNode agentFocusNode;
  final bool isCompact;
  final VoidCallback onAgentSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final Widget clientField = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: AppTextField(
        label: l10n.ctFieldClientId,
        controller: clientIdController,
        hint: l10n.ctHintClientId,
        readOnly: true,
        suffixIcon: ClientTokenCopyValueButton(value: clientIdController.text),
      ),
    );

    final Widget agentField = FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: AppTextField(
        label: l10n.ctFieldAgentIdOptional,
        controller: agentIdController,
        hint: l10n.ctHintAgentId,
        focusNode: agentFocusNode,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onAgentSubmitted(),
      ),
    );

    if (isCompact) {
      return Column(
        children: [
          clientField,
          const SizedBox(height: AppSpacing.md),
          agentField,
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: clientField),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 2, child: agentField),
      ],
    );
  }
}

class ClientTokenCopyValueButton extends StatelessWidget {
  const ClientTokenCopyValueButton({required this.value, super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(FluentIcons.copy, size: 16),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
      },
    );
  }
}

class ClientTokenFeedbackPanel extends StatelessWidget {
  const ClientTokenFeedbackPanel({
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onDismissCreatedToken,
    super.key,
  });

  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final VoidCallback onDismissCreatedToken;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedbackWidgets = <Widget>[
      if (formError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: formError,
        ),
      if (providerError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: providerError,
        ),
      if (lastCreatedToken != null)
        InlineFeedbackCard(
          severity: InfoBarSeverity.success,
          title: l10n.ctMsgTokenCreatedCopyNow,
          content: SelectableText(lastCreatedToken!),
          onDismiss: onDismissCreatedToken,
        ),
    ];

    if (feedbackWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: List<Widget>.generate(feedbackWidgets.length, (index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == feedbackWidgets.length - 1 ? 0 : AppSpacing.md,
            ),
            child: feedbackWidgets[index],
          );
        }),
      ),
    );
  }
}

class ClientTokenFlagCheckbox extends StatelessWidget {
  const ClientTokenFlagCheckbox({
    required this.focusOrder,
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final double focusOrder;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: Checkbox(
        checked: value,
        onChanged: (isChecked) => onChanged(isChecked ?? false),
        content: Text(label),
      ),
    );
  }
}

class ClientTokenPermissionToggle extends StatelessWidget {
  const ClientTokenPermissionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
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
