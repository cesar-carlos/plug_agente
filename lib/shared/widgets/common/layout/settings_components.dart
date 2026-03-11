import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageHorizontal,
      vertical: AppSpacing.settingsSectionVertical,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: FluentTheme.of(context).typography.subtitle,
    );
  }
}

class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
        ),
        ToggleSwitch(checked: value, onChanged: onChanged),
      ],
    );
  }
}

class SettingsKeyValue extends StatelessWidget {
  const SettingsKeyValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: typography.bodyStrong),
        Text(value, style: typography.body),
      ],
    );
  }
}
