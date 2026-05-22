import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Compact contextual help affordance for form labels.
///
/// Prefer passing a stable [key] from the labeled form field. Keep [title] short
/// and [message] focused on decision impact, not on restating the field label.
class AppHelpButton extends StatefulWidget {
  const AppHelpButton({
    required this.title,
    required this.message,
    super.key,
    this.tooltip,
    this.semanticLabel,
    this.semanticHint,
  });

  final String title;
  final String message;
  final String? tooltip;
  final String? semanticLabel;
  final String? semanticHint;

  @override
  State<AppHelpButton> createState() => _AppHelpButtonState();
}

class _AppHelpButtonState extends State<AppHelpButton> {
  static const double _flyoutWidth = 320;

  late final FlyoutController _controller = FlyoutController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showHelp() {
    return _controller.showFlyout<void>(
      autoModeConfiguration: FlyoutAutoConfiguration(
        preferredMode: FlyoutPlacementMode.bottomRight,
      ),
      builder: (context) {
        return FlyoutContent(
          constraints: const BoxConstraints(maxWidth: _flyoutWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: context.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              Text(widget.message, style: context.bodyText),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = widget.tooltip ?? widget.title;
    return FlyoutTarget(
      controller: _controller,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: widget.semanticLabel ?? tooltip,
          hint: widget.semanticHint ?? widget.message,
          child: SizedBox.square(
            dimension: 24,
            child: IconButton(
              icon: Icon(
                FluentIcons.info,
                size: 14,
                color: context.appColors.textSecondary,
              ),
              onPressed: _showHelp,
            ),
          ),
        ),
      ),
    );
  }
}
