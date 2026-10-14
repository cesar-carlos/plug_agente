import 'package:flutter/widgets.dart';

/// Feedback shared by fields in a form without coupling them to its domain.
///
/// Text fields are addressed by [TextEditingController]. Dropdowns and other
/// controls use [keyedErrors], [requiredKeys] and [focusKey].
class AppFormFeedbackScope extends InheritedWidget {
  const AppFormFeedbackScope({
    required this.errors,
    required this.requiredControllers,
    required this.requiredHint,
    required this.optionalHint,
    required this.focusController,
    required this.focusRequest,
    required this.onChanged,
    this.keyedErrors = const {},
    this.requiredKeys = const {},
    this.focusKey,
    this.onKeyedChanged,
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
  final Map<Object, String> keyedErrors;
  final Set<Object> requiredKeys;
  final Object? focusKey;
  final ValueChanged<Object>? onKeyedChanged;

  static AppFormFeedbackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppFormFeedbackScope>();

  @override
  bool updateShouldNotify(AppFormFeedbackScope oldWidget) {
    // Callers such as the action editor allocate a new map on every build.
    // Comparing entries keeps unchanged feedback from rebuilding every field.
    return focusRequest != oldWidget.focusRequest ||
        focusController != oldWidget.focusController ||
        focusKey != oldWidget.focusKey ||
        requiredHint != oldWidget.requiredHint ||
        optionalHint != oldWidget.optionalHint ||
        !_sameMap(errors, oldWidget.errors) ||
        !_sameSet(requiredControllers, oldWidget.requiredControllers) ||
        !_sameMap(keyedErrors, oldWidget.keyedErrors) ||
        !_sameSet(requiredKeys, oldWidget.requiredKeys);
  }
}

bool _sameMap<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

bool _sameSet<T>(Set<T> left, Set<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final value in left) {
    if (!right.contains(value)) return false;
  }
  return true;
}
