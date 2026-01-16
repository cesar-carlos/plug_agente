import 'package:fluent_ui/fluent_ui.dart';

class CenteredMessage extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const CenteredMessage({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.accentColor,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.typography.body,
            ),
          ],
        ),
      ),
    );
  }
}
