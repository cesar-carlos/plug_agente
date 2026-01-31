import 'package:fluent_ui/fluent_ui.dart';

class SqlActionBar extends StatelessWidget {
  const SqlActionBar({
    super.key,
    this.onExecute,
    this.onTestConnection,
    this.onClear,
    this.onCancel,
    this.isExecuting = false,
  });
  final VoidCallback? onExecute;
  final VoidCallback? onTestConnection;
  final VoidCallback? onClear;
  final VoidCallback? onCancel;
  final bool isExecuting;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isExecuting) ...[
          FilledButton(
            onPressed: onCancel,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                FluentTheme.of(
                  context,
                ).resources.systemFillColorCautionBackground,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProgressRing(strokeWidth: 2),
                SizedBox(width: 8),
                Text('Cancelar'),
              ],
            ),
          ),
        ] else ...[
          FilledButton(
            onPressed: onExecute,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Executar'),
                SizedBox(width: 8),
                _KeyboardShortcut(keys: 'F5'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Button(
            onPressed: onTestConnection,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Testar Conexão'),
                SizedBox(width: 8),
                _KeyboardShortcut(keys: 'Ctrl+Shift+C'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Button(
            onPressed: onClear,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Limpar'),
                SizedBox(width: 8),
                _KeyboardShortcut(keys: 'Ctrl+L'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _KeyboardShortcut extends StatelessWidget {
  const _KeyboardShortcut({required this.keys});
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Text(
      keys,
      style: TextStyle(
        fontSize: 11,
        color: FluentTheme.of(context).resources.textFillColorTertiary,
      ),
    );
  }
}
