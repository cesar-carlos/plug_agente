import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_colors.dart';

class ErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorWidget({super.key, required this.title, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final textColor = theme.typography.body?.color;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.error_badge, color: AppColors.error, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: textColor),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Tentar Novamente')),
          ],
        ],
      ),
    );
  }
}
