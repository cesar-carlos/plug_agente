import 'package:fluent_ui/fluent_ui.dart';

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
    return InfoLabel(
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: ComboBox<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          placeholder: placeholder ?? Text('Selecione $label'),
        ),
      ),
    );
  }
}
