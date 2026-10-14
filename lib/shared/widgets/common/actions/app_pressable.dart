import 'package:fluent_ui/fluent_ui.dart';

/// Keyboard-focusable press target with a visible focus border and click cursor.
class AppPressable extends StatelessWidget {
  const AppPressable({
    required this.onPressed,
    required this.child,
    super.key,
    this.semanticLabel,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onPressed,
      cursor: SystemMouseCursors.click,
      semanticLabel: semanticLabel,
      builder: (context, states) {
        return FocusBorder(
          focused: states.isFocused,
          child: child,
        );
      },
    );
  }
}
