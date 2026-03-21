import 'package:fluent_ui/fluent_ui.dart';

class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.leading,
    required this.trailing,
    this.spacing = 16,
    super.key,
  });

  final Widget leading;
  final Widget trailing;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        leading,
        trailing,
      ],
    );
  }
}
