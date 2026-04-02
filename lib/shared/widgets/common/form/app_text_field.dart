import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/form/app_labeled_field.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    super.key,
    this.fieldSpec,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.suffixIcon,
    this.prefixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.inputFormatters,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final FieldSpec? fieldSpec;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool enabled;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _touched = false;

  String? get _effectiveHint => widget.hint ?? widget.fieldSpec?.hint;

  TextInputType? get _effectiveKeyboardType =>
      widget.keyboardType ?? widget.fieldSpec?.keyboardType;

  String? Function(String?)? get _effectiveValidator =>
      widget.validator ?? widget.fieldSpec?.validator;

  List<TextInputFormatter> get _effectiveFormatters {
    final fromSpec =
        widget.fieldSpec?.formatters ?? const <TextInputFormatter>[];
    final explicit = widget.inputFormatters;
    if (explicit == null || explicit.isEmpty) {
      return fromSpec;
    }
    if (fromSpec.isEmpty) {
      return explicit;
    }
    return <TextInputFormatter>[...fromSpec, ...explicit];
  }

  String? get _errorText {
    if (!_touched) {
      return null;
    }
    final validate = _effectiveValidator;
    if (validate == null) {
      return null;
    }
    final text = widget.controller?.text ?? '';
    return validate(text);
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (_touched && mounted) {
      setState(() {});
    }
  }

  void _handleChanged(String value) {
    setState(() {
      _touched = true;
    });
    widget.onChanged?.call(value);
  }

  Widget? _buildPrefixIcon() {
    if (widget.prefixIcon == null) {
      return null;
    }

    if (widget.prefixIcon is Icon) {
      final icon = widget.prefixIcon! as Icon;
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(icon.icon, size: 18, color: icon.color),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: widget.prefixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textBox = TextBox(
      controller: widget.controller,
      placeholder: _effectiveHint,
      style: context.bodyText,
      obscureText: widget.obscureText,
      keyboardType: _effectiveKeyboardType,
      maxLines: widget.maxLines,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      inputFormatters: _effectiveFormatters,
      onChanged: _handleChanged,
      suffix: widget.suffixIcon,
      prefix: _buildPrefixIcon(),
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
    );

    return AppLabeledField(
      label: widget.label,
      errorText: _errorText,
      child: textBox,
    );
  }
}
