import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/shared/widgets/common/form/app_labeled_field.dart';

class AppDropdown<T> extends StatefulWidget {
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
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _touched = false;

  String? get _errorText {
    if (!_touched) {
      return null;
    }
    return widget.validator?.call(widget.value);
  }

  void _handleChanged(T? value) {
    setState(() {
      _touched = true;
    });
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final dropdown = SizedBox(
      width: double.infinity,
      child: ComboBox<T>(
        value: widget.value,
        items: widget.items,
        onChanged: _handleChanged,
        isExpanded: true,
        placeholder:
            widget.placeholder ??
            Text('${AppStrings.formDropdownSelectPrefix}${widget.label}'),
      ),
    );

    return AppLabeledField(
      label: widget.label,
      errorText: _errorText,
      child: dropdown,
    );
  }
}
