import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class SqlActionBar extends StatelessWidget {
  const SqlActionBar({
    super.key,
    this.onExecute,
    this.onTestConnection,
    this.onClear,
    this.onCancel,
    this.isExecuting = false,
    this.useStreamingMode = false,
    this.onStreamingModeChanged,
    this.streamingModeEnabled = false,
    this.onSqlHandlingModeChanged,
    this.sqlHandlingModePreserve = false,
  });
  final VoidCallback? onExecute;
  final VoidCallback? onTestConnection;
  final VoidCallback? onClear;
  final VoidCallback? onCancel;
  final bool isExecuting;
  final bool useStreamingMode;
  final ValueChanged<bool>? onStreamingModeChanged;
  final bool streamingModeEnabled;
  final ValueChanged<bool>? onSqlHandlingModeChanged;
  final bool sqlHandlingModePreserve;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actions = <_SqlActionConfig>[
      _SqlActionConfig(
        label: l10n.queryActionExecute,
        shortcut: 'F5',
        onPressed: onExecute,
        isPrimary: true,
      ),
      _SqlActionConfig(
        label: l10n.queryActionTestConnection,
        shortcut: 'Ctrl+Shift+C',
        onPressed: onTestConnection,
      ),
      _SqlActionConfig(
        label: l10n.queryActionClear,
        shortcut: 'Ctrl+L',
        onPressed: onClear,
      ),
    ];

    return Row(
      children: [
        if (onSqlHandlingModeChanged != null) ...[
          Tooltip(
            message: l10n.querySqlHandlingModePreserveHint,
            child: ToggleSwitch(
              checked: sqlHandlingModePreserve,
              onChanged: isExecuting ? null : onSqlHandlingModeChanged,
              content: Text(l10n.querySqlHandlingModePreserve),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
        if (useStreamingMode && onStreamingModeChanged != null) ...[
          Tooltip(
            message: l10n.queryStreamingModeHint,
            child: ToggleSwitch(
              checked: streamingModeEnabled,
              onChanged: isExecuting ? null : onStreamingModeChanged,
              content: Text(l10n.queryStreamingMode),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ProgressRing(strokeWidth: 2),
                          const SizedBox(width: AppSpacing.sm),
                          Text(l10n.queryActionCancel),
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
              ),
            ),
          ),
        ),
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
      style: context.bodyMuted.copyWith(
        fontSize: 11,
      ),
    );
  }
}
