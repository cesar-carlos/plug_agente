import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/iana_timezone_id_field.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_dialog_title_bar.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:uuid/uuid.dart';

abstract final class _AgentActionTriggerDialogKeys {
  static const ValueKey<String> surface = ValueKey<String>('agent_action_trigger_dialog_surface');
  static const ValueKey<String> scroll = ValueKey<String>('agent_action_trigger_dialog_scroll');
}

Future<void> showAgentActionTriggerSaveDialog({
  required BuildContext context,
  required AgentActionsProvider provider,
  required AppLocalizations l10n,
  required String actionId,
  AgentActionTrigger? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AgentActionTriggerSaveDialog(
        provider: provider,
        l10n: l10n,
        actionId: actionId,
        existing: existing,
      );
    },
  );
}

class AgentActionTriggerSaveDialog extends StatefulWidget {
  const AgentActionTriggerSaveDialog({
    required this.provider,
    required this.l10n,
    required this.actionId,
    super.key,
    this.existing,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;
  final AgentActionTrigger? existing;

  @override
  State<AgentActionTriggerSaveDialog> createState() => _AgentActionTriggerSaveDialogState();
}

class _AgentActionTriggerSaveDialogState extends State<AgentActionTriggerSaveDialog> {
  static const double _baseContentWidth = 720;
  static const double _baseContentHeight = 560;
  static const double _compactDialogMargin = 64;
  static const double _dialogChromeWidth = 176;
  static const double _dialogChromeHeight = 180;
  static const double _twoColumnBreakpoint = 640;

  late final TextEditingController _nameController;
  late final TextEditingController _timezoneController;
  late final TextEditingController _startAtController;
  late final TextEditingController _endAtController;
  late final TextEditingController _intervalMinutesController;
  late final TextEditingController _timeOfDayController;
  late final TextEditingController _dayOfMonthController;

  late AgentActionTriggerType _type;
  late bool _isEnabled;
  late bool _ignoreMissedRuns;
  late Set<int> _weekdays;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    final initialType = existing?.type;
    final initialSupportsTimezone =
        initialType == AgentActionTriggerType.daily ||
        initialType == AgentActionTriggerType.weekly ||
        initialType == AgentActionTriggerType.monthly;
    _timezoneController = TextEditingController(
      text: initialSupportsTimezone ? (existing?.schedule.timezoneId ?? '') : '',
    );
    _startAtController = TextEditingController(text: _formatDateTimeForField(existing?.schedule.startAt));
    _endAtController = TextEditingController(text: _formatDateTimeForField(existing?.schedule.endAt));
    _intervalMinutesController = TextEditingController(
      text: existing?.schedule.interval == null ? '' : '${existing!.schedule.interval!.inMinutes}',
    );
    _timeOfDayController = TextEditingController(text: _formatTimeOfDay(existing?.schedule.timeOfDayMinutes));
    _dayOfMonthController = TextEditingController(
      text: existing?.schedule.dayOfMonth == null ? '' : '${existing!.schedule.dayOfMonth}',
    );
    _type = existing?.type ?? AgentActionTriggerType.manual;
    _isEnabled = existing?.isEnabled ?? true;
    _ignoreMissedRuns = existing?.schedule.ignoreMissedRuns ?? true;
    _weekdays = {...?existing?.schedule.weekdays};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _startAtController.dispose();
    _endAtController.dispose();
    _intervalMinutesController.dispose();
    _timeOfDayController.dispose();
    _dayOfMonthController.dispose();
    super.dispose();
  }

  static String _formatDateTimeForField(DateTime? value) {
    if (value == null) {
      return '';
    }

    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatTimeOfDay(int? minutes) {
    if (minutes == null || minutes < 0 || minutes >= Duration.minutesPerDay) {
      return '';
    }

    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static DateTime? _tryParseLocalDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.contains('T') ? trimmed : trimmed.replaceFirst(RegExp(r'\s+'), 'T');
    return DateTime.tryParse(normalized);
  }

  static int? _tryParseTimeOfDayMinutes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parts = trimmed.split(':');
    if (parts.length != 2) {
      return null;
    }

    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) {
      return null;
    }

    if (h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }

    return h * Duration.minutesPerHour + m;
  }

  String? _timezoneOrNull() {
    final trimmed = _timezoneController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _onTriggerTypeChanged(AgentActionTriggerType value) async {
    final previous = _type;
    if (value == AgentActionTriggerType.appClose && previous != AgentActionTriggerType.appClose) {
      final confirmed = await confirmAppCloseTrigger(
        context: context,
        l10n: widget.l10n,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      final wasTemporal =
          previous == AgentActionTriggerType.daily ||
          previous == AgentActionTriggerType.weekly ||
          previous == AgentActionTriggerType.monthly;
      final nowTemporal =
          value == AgentActionTriggerType.daily ||
          value == AgentActionTriggerType.weekly ||
          value == AgentActionTriggerType.monthly;
      if (wasTemporal && !nowTemporal) {
        _timezoneController.clear();
      }
      _type = value;
    });
  }

  bool get _supportsMissedRunPolicy {
    return switch (_type) {
      AgentActionTriggerType.once ||
      AgentActionTriggerType.interval ||
      AgentActionTriggerType.daily ||
      AgentActionTriggerType.weekly ||
      AgentActionTriggerType.monthly => true,
      AgentActionTriggerType.manual ||
      AgentActionTriggerType.remote ||
      AgentActionTriggerType.appStart ||
      AgentActionTriggerType.appClose => false,
    };
  }

  AgentActionTrigger? _tryBuildTrigger() {
    setState(() {
      _parseError = null;
    });

    final l10n = widget.l10n;
    final existing = widget.existing;
    final id = existing?.id ?? const Uuid().v4();
    final nameRaw = _nameController.text.trim();
    final name = nameRaw.isEmpty ? null : nameRaw;

    AgentActionTriggerSchedule schedule;
    switch (_type) {
      case AgentActionTriggerType.manual:
      case AgentActionTriggerType.remote:
      case AgentActionTriggerType.appStart:
      case AgentActionTriggerType.appClose:
        schedule = const AgentActionTriggerSchedule();
      case AgentActionTriggerType.once:
        final startAt = _tryParseLocalDateTime(_startAtController.text);
        if (startAt == null) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidStartAt;
          });
          return null;
        }

        final endAtOnce = _tryParseLocalDateTime(_endAtController.text);
        schedule = AgentActionTriggerSchedule(
          startAt: startAt,
          endAt: endAtOnce,
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.interval:
        final minutes = int.tryParse(_intervalMinutesController.text.trim());
        if (minutes == null || minutes <= 0) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidIntervalMinutes;
          });
          return null;
        }

        final startAtInterval = _tryParseLocalDateTime(_startAtController.text);
        final endAtInterval = _tryParseLocalDateTime(_endAtController.text);
        schedule = AgentActionTriggerSchedule(
          interval: Duration(minutes: minutes),
          startAt: startAtInterval,
          endAt: endAtInterval,
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.daily:
        final timeMinutes = _tryParseTimeOfDayMinutes(_timeOfDayController.text);
        if (timeMinutes == null) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          });
          return null;
        }

        final startDaily = _tryParseLocalDateTime(_startAtController.text);
        final endDaily = _tryParseLocalDateTime(_endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeMinutes,
          startAt: startDaily,
          endAt: endDaily,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.weekly:
        final timeWeekly = _tryParseTimeOfDayMinutes(_timeOfDayController.text);
        if (timeWeekly == null) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          });
          return null;
        }

        if (_weekdays.isEmpty || _weekdays.any((int day) => day < 1 || day > 7)) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationWeekdaysRequired;
          });
          return null;
        }

        final startWeekly = _tryParseLocalDateTime(_startAtController.text);
        final endWeekly = _tryParseLocalDateTime(_endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeWeekly,
          weekdays: _weekdays,
          startAt: startWeekly,
          endAt: endWeekly,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.monthly:
        final timeMonthly = _tryParseTimeOfDayMinutes(_timeOfDayController.text);
        if (timeMonthly == null) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          });
          return null;
        }

        final day = int.tryParse(_dayOfMonthController.text.trim());
        if (day == null || day < 1 || day > 31) {
          setState(() {
            _parseError = l10n.agentActionsTriggerValidationInvalidDayOfMonth;
          });
          return null;
        }

        final startMonthly = _tryParseLocalDateTime(_startAtController.text);
        final endMonthly = _tryParseLocalDateTime(_endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeMonthly,
          dayOfMonth: day,
          startAt: startMonthly,
          endAt: endMonthly,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
    }

    return AgentActionTrigger(
      id: id,
      actionId: widget.actionId,
      type: _type,
      name: name,
      isEnabled: _isEnabled,
      schedule: schedule,
      lastScheduledAt: existing?.lastScheduledAt,
      lastRunAt: existing?.lastRunAt,
      nextRunAt: existing?.nextRunAt,
      createdAt: existing?.createdAt,
    );
  }

  Future<void> _handleSave() async {
    final built = _tryBuildTrigger();
    if (built == null) {
      return;
    }

    final ok = await widget.provider.saveTrigger(built);
    if (!mounted) {
      return;
    }

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  Size _dialogContentSize(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidthCandidate = screenSize.width - (_compactDialogMargin * 2) - _dialogChromeWidth;
    final maxHeightCandidate = screenSize.height - _dialogChromeHeight - _compactDialogMargin;
    final maxWidth = maxWidthCandidate < 360 ? 360.toDouble() : maxWidthCandidate;
    final maxHeight = maxHeightCandidate < 320 ? 320.toDouble() : maxHeightCandidate;

    return Size(
      math.min(_baseContentWidth, maxWidth),
      math.min(_baseContentHeight, maxHeight),
    );
  }

  Widget _buildDialogContent({
    required String? remoteError,
    required AppLocalizations l10n,
    required AgentActionsProvider provider,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final useTwoColumns = screenWidth >= 900 && constraints.maxWidth >= _twoColumnBreakpoint;
        return SingleChildScrollView(
          key: _AgentActionTriggerDialogKeys.scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildDialogFields(
              remoteError: remoteError,
              l10n: l10n,
              provider: provider,
              useTwoColumns: useTwoColumns,
              availableWidth: constraints.maxWidth,
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildDialogFields({
    required String? remoteError,
    required AppLocalizations l10n,
    required AgentActionsProvider provider,
    required bool useTwoColumns,
    required double availableWidth,
  }) {
    final children = <Widget>[];

    void addField(Widget field, {double spacing = AppSpacing.sm}) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: spacing));
      }
      children.add(field);
    }

    if (_parseError != null) {
      addField(
        InfoBar(
          title: Text(l10n.agentActionsTriggerValidationTitle),
          content: Text(_parseError!),
          severity: InfoBarSeverity.warning,
        ),
        spacing: 0,
      );
    }

    if (remoteError != null) {
      addField(
        InfoBar(
          title: Text(l10n.agentActionsErrorTitle),
          content: Text(remoteError),
          severity: InfoBarSeverity.error,
        ),
      );
    }

    addField(
      Checkbox(
        checked: _isEnabled,
        onChanged: provider.isSavingTrigger
            ? null
            : (bool? value) {
                setState(() {
                  _isEnabled = value ?? false;
                });
              },
        content: Text(l10n.agentActionsTriggerEnabled),
      ),
      spacing: children.isEmpty ? 0 : AppSpacing.sm,
    );

    addField(
      AppTextField(
        controller: _nameController,
        label: l10n.agentActionsTriggerFieldName,
        enabled: !provider.isSavingTrigger,
      ),
    );
    addField(
      AppDropdown<AgentActionTriggerType>(
        label: l10n.agentActionsTriggerFieldType,
        value: _type,
        items: AgentActionTriggerType.values
            .map(
              (AgentActionTriggerType value) => ComboBoxItem<AgentActionTriggerType>(
                value: value,
                child: Text(_triggerTypeLabel(value, l10n)),
              ),
            )
            .toList(growable: false),
        onChanged: provider.isSavingTrigger
            ? null
            : (AgentActionTriggerType? value) {
                if (value == null) {
                  return;
                }

                unawaited(_onTriggerTypeChanged(value));
              },
      ),
    );

    _buildScheduleFields(
      l10n: l10n,
      provider: provider,
      useTwoColumns: useTwoColumns,
    ).forEach(addField);

    if (_supportsMissedRunPolicy) {
      addField(
        Checkbox(
          checked: _ignoreMissedRuns,
          onChanged: provider.isSavingTrigger
              ? null
              : (bool? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _ignoreMissedRuns = value;
                  });
                },
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.agentActionsTriggerFieldIgnoreMissedRuns),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: math.max(
                  0,
                  math.min(availableWidth - 128, 360),
                ),
                child: Text(
                  l10n.agentActionsTriggerHintIgnoreMissedRuns,
                  style: context.bodyMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return children;
  }

  List<Widget> _buildScheduleFields({
    required AppLocalizations l10n,
    required AgentActionsProvider provider,
    required bool useTwoColumns,
  }) {
    final enabled = !provider.isSavingTrigger;
    final fields = <Widget>[];

    switch (_type) {
      case AgentActionTriggerType.manual:
      case AgentActionTriggerType.remote:
      case AgentActionTriggerType.appStart:
      case AgentActionTriggerType.appClose:
        return fields;
      case AgentActionTriggerType.once:
        fields.add(
          _fieldPair(
            useTwoColumns: useTwoColumns,
            first: AppTextField(
              controller: _startAtController,
              label: l10n.agentActionsTriggerFieldStartAt,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
            second: AppTextField(
              controller: _endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          ),
        );
      case AgentActionTriggerType.interval:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AppTextField(
                controller: _intervalMinutesController,
                label: l10n.agentActionsTriggerFieldIntervalMinutes,
                enabled: enabled,
              ),
              second: AppTextField(
                controller: _startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AppTextField(
              controller: _endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          );
      case AgentActionTriggerType.daily:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AppTextField(
                controller: _timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AppTextField(
              controller: _endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _timezoneController,
              enabled: enabled,
              l10n: l10n,
            ),
          );
      case AgentActionTriggerType.weekly:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AppTextField(
                controller: _timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(_buildWeekdaySelector(l10n, provider))
          ..add(
            AppTextField(
              controller: _endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _timezoneController,
              enabled: enabled,
              l10n: l10n,
            ),
          );
      case AgentActionTriggerType.monthly:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AppTextField(
                controller: _timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _dayOfMonthController,
                label: l10n.agentActionsTriggerFieldDayOfMonth,
                enabled: enabled,
              ),
            ),
          )
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AppTextField(
                controller: _startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
              second: AppTextField(
                controller: _endAtController,
                label: l10n.agentActionsTriggerFieldEndAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _timezoneController,
              enabled: enabled,
              l10n: l10n,
            ),
          );
    }

    return _withVerticalGaps(fields);
  }

  Widget _buildWeekdaySelector(AppLocalizations l10n, AgentActionsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsTriggerFieldWeekdays, style: context.bodyText),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final int day in const <int>[1, 2, 3, 4, 5, 6, 7])
              Checkbox(
                checked: _weekdays.contains(day),
                onChanged: provider.isSavingTrigger
                    ? null
                    : (bool? checked) {
                        setState(() {
                          if (checked ?? false) {
                            _weekdays.add(day);
                          } else {
                            _weekdays.remove(day);
                          }
                        });
                      },
                content: Text(_weekdayLabel(day, l10n)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _fieldPair({
    required bool useTwoColumns,
    required Widget first,
    required Widget second,
  }) {
    if (!useTwoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: AppSpacing.sm),
          second,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: second),
      ],
    );
  }

  List<Widget> _withVerticalGaps(List<Widget> fields) {
    final spaced = <Widget>[];
    for (final field in fields) {
      if (spaced.isNotEmpty) {
        spaced.add(const SizedBox(height: AppSpacing.sm));
      }
      spaced.add(field);
    }
    return spaced;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEditing = widget.existing != null;
    final provider = widget.provider;
    final contentSize = _dialogContentSize(context);

    return ListenableBuilder(
      listenable: provider,
      builder: (BuildContext context, Widget? child) {
        final remoteError = provider.triggerErrorMessage;

        return ContentDialog(
          constraints: BoxConstraints(
            minWidth: contentSize.width + _dialogChromeWidth,
            maxWidth: contentSize.width + _dialogChromeWidth,
            maxHeight: contentSize.height + _dialogChromeHeight,
          ),
          title: AppDialogTitleBar(
            title: Text(isEditing ? l10n.agentActionsTriggerEditorTitleEdit : l10n.agentActionsTriggerEditorTitleNew),
            closeTooltip: l10n.btnClose,
            canClose: !provider.isSavingTrigger,
            onClose: () => Navigator.pop(context),
          ),
          content: SizedBox(
            key: _AgentActionTriggerDialogKeys.surface,
            width: contentSize.width,
            height: contentSize.height,
            child: _buildDialogContent(
              remoteError: remoteError,
              l10n: l10n,
              provider: provider,
            ),
          ),
          actions: [
            Button(
              onPressed: provider.isSavingTrigger ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.agentActionsTriggerCancel),
            ),
            FilledButton(
              onPressed: provider.isSavingTrigger || !provider.isFeatureEnabled ? null : _handleSave,
              child: provider.isSavingTrigger
                  ? const SizedBox.square(
                      dimension: 16,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Text(l10n.agentActionsTriggerSave),
            ),
          ],
        );
      },
    );
  }
}

String _triggerTypeLabel(AgentActionTriggerType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionTriggerType.manual => l10n.agentActionsTriggerTypeManual,
    AgentActionTriggerType.remote => l10n.agentActionsTriggerTypeRemote,
    AgentActionTriggerType.once => l10n.agentActionsTriggerTypeOnce,
    AgentActionTriggerType.interval => l10n.agentActionsTriggerTypeInterval,
    AgentActionTriggerType.daily => l10n.agentActionsTriggerTypeDaily,
    AgentActionTriggerType.weekly => l10n.agentActionsTriggerTypeWeekly,
    AgentActionTriggerType.monthly => l10n.agentActionsTriggerTypeMonthly,
    AgentActionTriggerType.appStart => l10n.agentActionsTriggerTypeAppStart,
    AgentActionTriggerType.appClose => l10n.agentActionsTriggerTypeAppClose,
  };
}

String _weekdayLabel(int weekday, AppLocalizations l10n) {
  return switch (weekday) {
    1 => l10n.agentActionsTriggerWeekdayMon,
    2 => l10n.agentActionsTriggerWeekdayTue,
    3 => l10n.agentActionsTriggerWeekdayWed,
    4 => l10n.agentActionsTriggerWeekdayThu,
    5 => l10n.agentActionsTriggerWeekdayFri,
    6 => l10n.agentActionsTriggerWeekdaySat,
    7 => l10n.agentActionsTriggerWeekdaySun,
    _ => '$weekday',
  };
}
