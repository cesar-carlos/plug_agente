import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

class ClientTokenCreateDialogFooter extends StatelessWidget {
  const ClientTokenCreateDialogFooter({
    required this.isCreating,
    required this.canSubmit,
    required this.submitLabel,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  final bool isCreating;
  final bool canSubmit;
  final String submitLabel;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final submitEnabled = !isCreating && canSubmit;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(200),
          child: AppButton(
            label: l10n.btnCancel,
            isPrimary: false,
            onPressed: isCreating ? null : onCancel,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FocusTraversalOrder(
          order: const NumericFocusOrder(210),
          child: AppButton(
            label: submitLabel,
            isLoading: isCreating,
            onPressed: submitEnabled ? onSubmit : null,
          ),
        ),
      ],
    );
  }
}
