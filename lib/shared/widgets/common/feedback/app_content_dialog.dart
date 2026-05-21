import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_dialog_title_bar.dart';

class AppContentDialog extends StatelessWidget {
  const AppContentDialog({
    required this.title,
    required this.closeTooltip,
    required this.content,
    super.key,
    this.leading,
    this.onClose,
    this.canClose = true,
    this.actions,
    this.maxWidth,
    this.maxHeight,
    this.contentWidth,
    this.contentHeight,
  });

  final Widget title;
  final Widget? leading;
  final String closeTooltip;
  final VoidCallback? onClose;
  final bool canClose;
  final Widget content;
  final List<Widget>? actions;
  final double? maxWidth;
  final double? maxHeight;
  final double? contentWidth;
  final double? contentHeight;

  @override
  Widget build(BuildContext context) {
    var dialogContent = content;
    if (contentWidth != null || contentHeight != null) {
      dialogContent = SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: content,
      );
    }

    return ContentDialog(
      constraints: maxWidth == null && maxHeight == null
          ? kDefaultContentDialogConstraints
          : BoxConstraints(
              maxWidth: maxWidth ?? double.infinity,
              maxHeight: maxHeight ?? double.infinity,
            ),
      title: AppDialogTitleBar(
        leading: leading,
        title: title,
        closeTooltip: closeTooltip,
        canClose: canClose,
        onClose: onClose,
      ),
      content: dialogContent,
      actions: actions,
    );
  }
}
