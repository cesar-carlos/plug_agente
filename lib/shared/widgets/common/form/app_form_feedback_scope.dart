import 'package:flutter/widgets.dart';

/// Feedback shared by fields in a form without coupling them to its domain.
class AppFormFeedbackScope extends InheritedWidget {
  const AppFormFeedbackScope({
    required this.errors,
    required this.requiredControllers,
    required this.requiredHint,
    required this.optionalHint,
    required this.focusController,
    required this.focusRequest,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final Map<TextEditingController, String> errors;
  final Set<TextEditingController> requiredControllers;
  final String requiredHint;
  final String optionalHint;
  final TextEditingController? focusController;
  final int focusRequest;
  final ValueChanged<TextEditingController> onChanged;

  static AppFormFeedbackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppFormFeedbackScope>();

  @override
  bool updateShouldNotify(AppFormFeedbackScope oldWidget) => true;
}
