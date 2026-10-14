import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_form_feedback_scope.dart';
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
    this.helpTitle,
    this.helpMessage,
    this.helpTooltip,
    this.helpButtonKey,
    this.reserveHelpAffordance = false,
    this.labelMinLines = 1,
    this.feedbackKey,
    this.helperText,
  });

  final String label;
  final T? value;
  final List<ComboBoxItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final Widget? placeholder;
  final String? helpTitle;
  final String? helpMessage;
  final String? helpTooltip;
  final Key? helpButtonKey;
  final bool reserveHelpAffordance;
  final int labelMinLines;
  final Object? feedbackKey;
  final String? helperText;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _touched = false;
  final FocusNode _focusNode = FocusNode();
  int _lastFocusRequest = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final feedback = AppFormFeedbackScope.maybeOf(context);
    final key = widget.feedbackKey;
    if (feedback == null || key == null || feedback.focusKey != key || feedback.focusRequest == _lastFocusRequest) {
      return;
    }
    _lastFocusRequest = feedback.focusRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      Scrollable.ensureVisible(context, alignment: 0.2);
    });
  }

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
    final key = widget.feedbackKey;
    if (key != null) {
      AppFormFeedbackScope.maybeOf(context)?.onKeyedChanged?.call(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedback = AppFormFeedbackScope.maybeOf(context);
    final key = widget.feedbackKey;
    final isRequired = key != null && (feedback?.requiredKeys.contains(key) ?? false);
    final scopeError = key == null ? null : feedback?.keyedErrors[key];
    final dropdown = SizedBox(
      width: double.infinity,
      child: ComboBox<T>(
        value: widget.value,
        items: widget.items,
        onChanged: widget.onChanged == null ? null : _handleChanged,
        isExpanded: true,
        focusNode: _focusNode,
        placeholder: widget.placeholder ?? Text('${l10n.formDropdownSelectPrefix}${widget.label}'),
      ),
    );

    return AppLabeledField(
      label: widget.label,
      errorText: scopeError ?? _errorText,
      helperText:
          widget.helperText ??
          (feedback == null
              ? null
              : isRequired
              ? feedback.requiredHint
              : feedback.optionalHint),
      helpTitle: widget.helpTitle,
      helpMessage: widget.helpMessage,
      helpTooltip: widget.helpTooltip,
      helpButtonKey: widget.helpButtonKey,
      reserveHelpAffordance: widget.reserveHelpAffordance,
      labelMinLines: widget.labelMinLines,
      child: dropdown,
    );
  }
}
