import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// [InfoLabel] + child control + optional inline error (shared by form fields).
class AppLabeledField extends StatelessWidget {
  const AppLabeledField({
    required this.label,
    required this.child,
    super.key,
    this.errorText,
  });

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final trimmed = errorText?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return InfoLabel(
        label: label,
        labelStyle: context.bodyStrong,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: AppSpacing.xs),
            Text(
              trimmed,
              style: context.bodyMuted.copyWith(
                color: AppColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return InfoLabel(
      label: label,
      labelStyle: context.bodyStrong,
      child: child,
    );
  }
}
