import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

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
      style: context.sectionTitle,
    );
  }
}

class SettingsSectionBlock extends StatelessWidget {
  const SettingsSectionBlock({
    required this.title,
    required this.child,
    super.key,
    this.spacing = AppSpacing.md,
  });

  final String title;
  final Widget child;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(title: title),
        SizedBox(height: spacing),
        child,
      ],
    );
  }
}

class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final onChanged = this.onChanged;
    final isEnabled = onChanged != null;
    final labelStyle = context.bodyStrong.copyWith(
      color: isEnabled ? null : theme.inactiveColor,
    );
    final description = this.description;

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: labelStyle,
              ),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: context.captionText.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ],
            ],
          ),
        ),
        ExcludeSemantics(
          child: ToggleSwitch(checked: value, onChanged: onChanged),
        ),
      ],
    );

    if (!isEnabled) {
      return row;
    }

    // The whole tile acts as the toggle target so the label and description are
    // clickable, not just the switch. Semantics on the switch are excluded to
    // avoid a duplicated control announcement.
    return Semantics(
      toggled: value,
      label: label,
      hint: description,
      container: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: row,
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.bodyStrong),
        Text(value, style: context.bodyText),
      ],
    );
  }
}
