import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.label,
    required this.value,
    required this.items,
    super.key,
    this.onChanged,
    this.validator,
    this.placeholder,
  });
  final String label;
  final T? value;
  final List<ComboBoxItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final errorText = validator?.call(value);
    final dropdown = SizedBox(
      width: double.infinity,
      child: ComboBox<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        placeholder: placeholder ?? Text('Selecione $label'),
      ),
    );

    if (errorText != null && errorText.isNotEmpty) {
      return InfoLabel(
        label: label,
        labelStyle: context.bodyStrong,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            dropdown,
            const SizedBox(height: AppSpacing.xs),
            Text(
              errorText,
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
      child: dropdown,
    );
  }
}
