import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_pressable.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding,
    this.margin,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
      margin: margin ?? EdgeInsets.zero,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: child,
    );

    final onTap = this.onTap;
    if (onTap != null) {
      return AppPressable(onPressed: onTap, child: card);
    }

    return card;
  }
}
