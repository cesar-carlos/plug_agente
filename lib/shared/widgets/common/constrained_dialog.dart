import 'package:fluent_ui/fluent_ui.dart';

enum DialogType { destination, schedule, sqlServerConfig, sybaseConfig }

class ConstrainedDialog extends StatelessWidget {
  const ConstrainedDialog({
    required this.child,
    required this.type,
    super.key,
    this.title,
  });
  final Widget child;
  final DialogType type;
  final String? title;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    required DialogType type,
    String? title,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) =>
          ConstrainedDialog(type: type, title: title, child: child),
    );
  }

  static BoxConstraints _getConstraints(DialogType type) {
    switch (type) {
      case DialogType.destination:
        return const BoxConstraints(maxWidth: 500, maxHeight: 400);
      case DialogType.schedule:
        return const BoxConstraints(maxWidth: 600, maxHeight: 500);
      case DialogType.sqlServerConfig:
        return const BoxConstraints(maxWidth: 700, maxHeight: 600);
      case DialogType.sybaseConfig:
        return const BoxConstraints(maxWidth: 700, maxHeight: 600);
    }
  }

  @override
  Widget build(BuildContext context) {
    final constraints = _getConstraints(type);

    return ContentDialog(
      title: title != null ? Text(title!) : null,
      content: ConstrainedBox(
        constraints: constraints,
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SingleChildScrollView(child: child),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
