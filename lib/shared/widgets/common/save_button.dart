import 'package:fluent_ui/fluent_ui.dart';

class SaveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isEditing;
  final bool isLoading;

  const SaveButton({
    super.key,
    required this.onPressed,
    this.isEditing = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.save),
                const SizedBox(width: 8),
                Text(isEditing ? 'Salvar' : 'Criar'),
              ],
            ),
    );
  }
}

