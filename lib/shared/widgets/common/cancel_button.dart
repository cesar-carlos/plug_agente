import 'package:fluent_ui/fluent_ui.dart';

class CancelButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const CancelButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      child: const Text('Cancelar'),
    );
  }
}

