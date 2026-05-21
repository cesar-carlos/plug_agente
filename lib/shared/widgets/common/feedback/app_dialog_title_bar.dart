import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppDialogTitleBar extends StatelessWidget {
  const AppDialogTitleBar({
    required this.title,
    required this.closeTooltip,
    super.key,
    this.leading,
    this.onClose,
    this.canClose = true,
  });

  final Widget title;
  final Widget? leading;
  final String closeTooltip;
  final VoidCallback? onClose;
  final bool canClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: DefaultTextStyle.merge(
            style: context.sectionTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: title,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Tooltip(
          message: closeTooltip,
          child: IconButton(
            icon: const Icon(FluentIcons.chrome_close),
            onPressed: canClose ? (onClose ?? () => Navigator.of(context).maybePop()) : null,
          ),
        ),
      ],
    );
  }
}
