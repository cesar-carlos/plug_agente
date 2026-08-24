import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AgentActionsEmptyState extends StatelessWidget {
  const AgentActionsEmptyState({
    required this.message,
    this.icon = FluentIcons.processing,
    this.detail,
    this.action,
    this.maxWidth = 560,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget? detail;
  final Widget? action;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - (AppSpacing.lg * 2)).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 36,
                      color: FluentTheme.of(context).accentColor,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      message,
                      style: context.sectionTitle,
                      textAlign: TextAlign.center,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      detail!,
                    ],
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
