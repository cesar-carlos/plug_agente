import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/form/app_help_button.dart';

/// [InfoLabel] + child control + optional inline error (shared by form fields).
class AppLabeledField extends StatelessWidget {
  const AppLabeledField({
    required this.label,
    required this.child,
    super.key,
    this.errorText,
    this.helpTitle,
    this.helpMessage,
    this.helpTooltip,
    this.helpButtonKey,
  });

  final String label;
  final Widget child;
  final String? errorText;
  final String? helpTitle;
  final String? helpMessage;
  final String? helpTooltip;
  final Key? helpButtonKey;

  bool get _hasHelp {
    return (helpTitle?.trim().isNotEmpty ?? false) && (helpMessage?.trim().isNotEmpty ?? false);
  }

  Key get _resolvedHelpButtonKey {
    return helpButtonKey ?? ValueKey<String>('app_help_button_${_keyToken(label)}');
  }

  String _keyToken(String value) {
    var token = value.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    while (token.startsWith('_')) {
      token = token.substring(1);
    }
    while (token.endsWith('_')) {
      token = token.substring(0, token.length - 1);
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = errorText?.trim();
    final colors = context.appColors;
    final content = trimmed != null && trimmed.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(height: AppSpacing.xs),
              Text(
                trimmed,
                style: context.bodyMuted.copyWith(
                  color: colors.error,
                  fontSize: 12,
                ),
              ),
            ],
          )
        : child;

    if (!_hasHelp) {
      return InfoLabel(
        label: label,
        labelStyle: context.bodyStrong,
        child: content,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final labelText = Text(
              label,
              style: context.bodyStrong,
            );
            return Row(
              children: [
                if (constraints.maxWidth.isFinite) Expanded(child: labelText) else Flexible(child: labelText),
                const SizedBox(width: AppSpacing.xs),
                AppHelpButton(
                  key: _resolvedHelpButtonKey,
                  title: helpTitle!.trim(),
                  message: helpMessage!.trim(),
                  tooltip: helpTooltip,
                  semanticLabel: '$label. ${helpTitle!.trim()}',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        content,
      ],
    );
  }
}
