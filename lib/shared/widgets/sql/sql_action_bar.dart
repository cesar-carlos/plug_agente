import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';

class SqlActionBar extends StatelessWidget {
  const SqlActionBar({
    super.key,
    this.onExecute,
    this.onTestConnection,
    this.onClear,
    this.onCancel,
    this.isExecuting = false,
  });
  final VoidCallback? onExecute;
  final VoidCallback? onTestConnection;
  final VoidCallback? onClear;
  final VoidCallback? onCancel;
  final bool isExecuting;

  @override
  Widget build(BuildContext context) {
    final actions = <_SqlActionConfig>[
      _SqlActionConfig(
        label: AppStrings.queryActionExecute,
        shortcut: 'F5',
        onPressed: onExecute,
        isPrimary: true,
      ),
      _SqlActionConfig(
        label: AppStrings.queryActionTestConnection,
        shortcut: 'Ctrl+Shift+C',
        onPressed: onTestConnection,
      ),
      _SqlActionConfig(
        label: AppStrings.queryActionClear,
        shortcut: 'Ctrl+L',
        onPressed: onClear,
      ),
    ];

    return Row(
      children: [
        if (isExecuting) ...[
          FilledButton(
            onPressed: onCancel,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                FluentTheme.of(
                  context,
                ).resources.systemFillColorCautionBackground,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProgressRing(strokeWidth: 2),
                SizedBox(width: AppSpacing.sm),
                Text(AppStrings.queryActionCancel),
              ],
            ),
          ),
        ] else ...[
          for (int index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            _SqlActionButton(config: actions[index]),
          ],
        ],
      ],
    );
  }
}

class _SqlActionButton extends StatelessWidget {
  const _SqlActionButton({required this.config});

  final _SqlActionConfig config;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(config.label),
        const SizedBox(width: AppSpacing.sm),
        _KeyboardShortcut(keys: config.shortcut),
      ],
    );

    if (config.isPrimary) {
      return FilledButton(onPressed: config.onPressed, child: child);
    }

    return Button(onPressed: config.onPressed, child: child);
  }
}

class _SqlActionConfig {
  const _SqlActionConfig({
    required this.label,
    required this.shortcut,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final String shortcut;
  final VoidCallback? onPressed;
  final bool isPrimary;
}

class _KeyboardShortcut extends StatelessWidget {
  const _KeyboardShortcut({required this.keys});
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Text(
      keys,
      style: TextStyle(
        fontSize: 11,
        color: FluentTheme.of(context).resources.textFillColorTertiary,
      ),
    );
  }
}
