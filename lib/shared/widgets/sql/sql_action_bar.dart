import 'package:fluent_ui/fluent_ui.dart';

class SqlActionBar extends StatelessWidget {
  final VoidCallback? onExecute;
  final VoidCallback? onTestConnection;
  final VoidCallback? onClear;
  final bool isExecuting;

  const SqlActionBar({
    super.key,
    this.onExecute,
    this.onTestConnection,
    this.onClear,
    this.isExecuting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton(
          onPressed: isExecuting ? null : onExecute,
          child: const Text('Executar'),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: isExecuting ? null : onTestConnection,
          child: const Text('Testar Conexão'),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: isExecuting ? null : onClear,
          child: const Text('Limpar'),
        ),
      ],
    );
  }
}
