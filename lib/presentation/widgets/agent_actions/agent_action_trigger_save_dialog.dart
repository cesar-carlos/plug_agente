import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/action_trigger_schedule_calculator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_datetime_field.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_coordinator.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_form_state.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_type_field.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_select_builder.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/iana_timezone_id_field.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_dialog_title_bar.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_form_feedback_scope.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
    builder: (context) {
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

  bool _submitted = false;
  int _focusRequest = 0;
  final GlobalKey _errorKey = GlobalKey();
  final GlobalKey _selectionErrorKey = GlobalKey();
  final _selectionFocus = FocusNode();
  late final AgentActionTriggerSaveFormState _formState;
  late final AgentActionTriggerSaveCoordinator _saveCoordinator;

  @override
  void initState() {
    super.initState();
    _formState = AgentActionTriggerSaveFormState(existing: widget.existing);
    for (final controller in _formState.controllers) {
      controller.addListener(_onFormChanged);
    }
    _saveCoordinator = AgentActionTriggerSaveCoordinator(
      formState: _formState,
      provider: widget.provider,
      l10n: widget.l10n,
      actionId: widget.actionId,
      existing: widget.existing,
    );
  }

  @override
  void dispose() {
    for (final controller in _formState.controllers) {
      controller.removeListener(_onFormChanged);
    }
    _selectionFocus.dispose();
    _formState.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  AgentActionDefinition? get _actionDefinition =>
      widget.provider.definitions.where((item) => item.id == widget.actionId).firstOrNull;

  Future<void> _onTriggerTypeChanged(AgentActionTriggerType value) async {
    final previous = _formState.type;
    if (value == AgentActionTriggerType.appClose && previous != AgentActionTriggerType.appClose) {
      final confirmed = await confirmAppCloseTrigger(
        context: context,
        l10n: widget.l10n,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() => _formState.applyTriggerTypeChange(value, previous: previous));
  }

  Future<void> _handleSave() async {
    setState(() => _submitted = true);
    final ok = await _saveCoordinator.save();
    if (!mounted) {
      return;
    }

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _focusRequest++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _formState.selectionError != null
            ? _selectionErrorKey.currentContext
            : _formState.fieldErrors.isEmpty
            ? _errorKey.currentContext
            : null;
        if (target != null) {
          Scrollable.ensureVisible(target, alignment: 0.2);
          if (_formState.selectionError != null) _selectionFocus.requestFocus();
        }
      });
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

    if (_submitted && _formState.parseError != null) {
      addField(
        InfoBar(
          title: Text(l10n.agentActionsTriggerValidationTitle),
          content: Text(_formState.parseError!),
          severity: InfoBarSeverity.warning,
        ),
        spacing: 0,
      );
    }

    if (remoteError != null) {
      addField(
        InfoBar(
          key: _errorKey,
          title: Text(l10n.agentActionsErrorTitle),
          content: Text(remoteError),
          severity: InfoBarSeverity.error,
        ),
      );
    }

    addField(
      Checkbox(
        checked: _formState.isEnabled,
        onChanged: provider.isSavingTrigger
            ? null
            : (value) {
                setState(() => _formState.setEnabled(value ?? false));
              },
        content: Text(l10n.agentActionsTriggerEnabled),
      ),
      spacing: children.isEmpty ? 0 : AppSpacing.sm,
    );

    addField(
      AppTextField(
        controller: _formState.nameController,
        label: l10n.agentActionsTriggerFieldName,
        enabled: !provider.isSavingTrigger,
      ),
    );
    addField(
      AgentActionTriggerTypeField(
        value: _formState.type,
        supports: (type) => _actionDefinition?.type.supportsTrigger(type) ?? true,
        labelFor: (type) => _triggerTypeLabel(type, l10n),
        onChanged: provider.isSavingTrigger ? null : (type) => unawaited(_onTriggerTypeChanged(type)),
      ),
    );

    addField(Text(l10n.agentActionsTriggerScheduleHint, style: context.bodyMuted));
    if (_actionDefinition?.type.isManualLocalOnly ?? false) {
      addField(
        InfoBar(
          title: Text(l10n.agentActionsTriggersTitle),
          content: Text(l10n.agentActionsTriggerCommandLineRestriction),
          isLong: true,
        ),
      );
    }
    if (_formState.type == AgentActionTriggerType.appClose) {
      addField(
        InfoBar(
          title: Text(l10n.agentActionsTriggerTypeAppClose),
          content: Text(l10n.agentActionsTriggerAppCloseRequirements),
          isLong: true,
        ),
      );
    }
    _buildScheduleFields(
      l10n: l10n,
      provider: provider,
      useTwoColumns: useTwoColumns,
    ).forEach(addField);

    if (_formState.supportsMissedRunPolicy) {
      addField(
        Checkbox(
          checked: _formState.ignoreMissedRuns,
          onChanged: provider.isSavingTrigger
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _formState.setIgnoreMissedRuns(value));
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

    if (_formState.type == AgentActionTriggerType.once && widget.existing?.lastScheduledAt != null) {
      addField(
        _selectionFeedback(
          'rearm',
          Checkbox(
            checked: _formState.rearmOnce,
            content: Text(l10n.triggerRearm),
            onChanged: provider.isSavingTrigger
                ? null
                : (value) => setState(() => _formState.rearmOnce = value ?? false),
          ),
        ),
      );
    }
    if (_formState.supportsMissedRunPolicy) {
      addField(Text(l10n.triggerLocalDates, style: context.bodyMuted));
      addField(_buildPreview(l10n));
    }
    return children;
  }

  Widget _selectionFeedback(String key, Widget child) {
    if (!_submitted || _formState.selectionErrorKey != key) return child;
    return Focus(
      key: _selectionErrorKey,
      focusNode: _selectionFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          Text(_formState.selectionError!, style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    final built = _formState.buildTrigger(l10n: l10n, actionId: widget.actionId, existing: widget.existing);
    var text = l10n.triggerPreviewIncomplete;
    final trigger = built.trigger;
    if (!_formState.isEnabled) {
      text = l10n.triggerPreviewDisabled;
    } else if (trigger != null) {
      final now = DateTime.now();
      final decision = const AgentActionTriggerScheduleCalculator().nextRun(trigger: trigger, now: now);
      final next = decision.getOrNull()?.nextRunAt;
      text = next == null
          ? l10n.triggerNoFutureRun
          : next.isBefore(now)
          ? l10n.triggerPreviewCatchUp
          : l10n.agentActionsTriggerNextRun(AgentActionTriggerSaveFormState.formatDateTimeForField(next));
    }
    return InfoBar(
      key: const ValueKey('trigger_schedule_preview'),
      title: Text(text),
      content: Text(l10n.triggerPreviewLocal),
      isLong: true,
    );
  }

  List<Widget> _buildScheduleFields({
    required AppLocalizations l10n,
    required AgentActionsProvider provider,
    required bool useTwoColumns,
  }) {
    final enabled = !provider.isSavingTrigger;
    final fields = <Widget>[];
    if (_formState.type == AgentActionTriggerType.daily ||
        _formState.type == AgentActionTriggerType.weekly ||
        _formState.type == AgentActionTriggerType.monthly) {
      final timezone = _formState.timezoneController.text.trim();
      fields.add(Text(timezone.isEmpty ? l10n.triggerLocalTime : l10n.agentActionsTriggerSummaryTimeZone(timezone)));
    }

    switch (_formState.type) {
      case AgentActionTriggerType.manual:
      case AgentActionTriggerType.remote:
      case AgentActionTriggerType.appStart:
      case AgentActionTriggerType.appClose:
        return fields;
      case AgentActionTriggerType.actionSucceeded:
      case AgentActionTriggerType.actionFailed:
        final definitions = provider.definitions.where((item) => item.id != widget.actionId).toList();
        final source = _formState.sourceActionIdController.text.trim();
        return [
          AppDropdown<String>(
            label: l10n.agentActionsTriggerSourceAction,
            feedbackKey: _formState.sourceActionIdController,
            value: source.isEmpty ? null : source,
            items: [
              for (final definition in definitions) ComboBoxItem(value: definition.id, child: Text(definition.name)),
              if (source.isNotEmpty && !definitions.any((item) => item.id == source))
                ComboBoxItem(value: source, enabled: false, child: Text(source)),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) setState(() => _formState.sourceActionIdController.text = value);
                  }
                : null,
          ),
        ];
      case AgentActionTriggerType.once:
        fields.add(
          _fieldPair(
            useTwoColumns: useTwoColumns,
            first: AgentActionTriggerDateTimeField(
              controller: _formState.startAtController,
              label: l10n.agentActionsTriggerFieldStartAt,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
            second: AgentActionTriggerDateTimeField(
              controller: _formState.endAtController,
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
                controller: _formState.intervalMinutesController,
                label: l10n.agentActionsTriggerFieldIntervalMinutes,
                enabled: enabled,
              ),
              second: AgentActionTriggerDateTimeField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AgentActionTriggerDateTimeField(
              controller: _formState.endAtController,
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
              first: AgentActionTriggerDateTimeField(
                timeOnly: true,
                controller: _formState.timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AgentActionTriggerDateTimeField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AgentActionTriggerDateTimeField(
              controller: _formState.endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _formState.timezoneController,
              enabled: enabled,
              l10n: l10n,
            ),
          );
      case AgentActionTriggerType.weekly:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AgentActionTriggerDateTimeField(
                timeOnly: true,
                controller: _formState.timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AgentActionTriggerDateTimeField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(_selectionFeedback('weekdays', _buildWeekdaySelector(l10n, provider)))
          ..add(
            AgentActionTriggerDateTimeField(
              controller: _formState.endAtController,
              label: l10n.agentActionsTriggerFieldEndAtOptional,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _formState.timezoneController,
              enabled: enabled,
              l10n: l10n,
            ),
          );
      case AgentActionTriggerType.monthly:
        fields
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AgentActionTriggerDateTimeField(
                timeOnly: true,
                controller: _formState.timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _formState.dayOfMonthController,
                label: l10n.agentActionsTriggerFieldDayOfMonth,
                enabled: enabled,
              ),
            ),
          )
          ..add(
            _fieldPair(
              useTwoColumns: useTwoColumns,
              first: AgentActionTriggerDateTimeField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
              second: AgentActionTriggerDateTimeField(
                controller: _formState.endAtController,
                label: l10n.agentActionsTriggerFieldEndAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            IanaTimezoneIdField(
              controller: _formState.timezoneController,
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
                checked: _formState.weekdays.contains(day),
                onChanged: provider.isSavingTrigger
                    ? null
                    : (checked) {
                        setState(() => _formState.toggleWeekday(day, checked ?? false));
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

    return AgentActionsSelectBuilder(
      listenable: provider,
      selector: () => Object.hash(
        provider.isSavingTrigger,
        provider.triggerErrorMessage,
        provider.isRemoteAgentActionsEnabled,
        Object.hashAll(provider.definitions),
      ),
      builder: (context) {
        final remoteError = provider.triggerErrorMessage;
        _formState.buildTrigger(l10n: l10n, actionId: widget.actionId, existing: widget.existing);

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
            child: AppFormFeedbackScope(
              errors: _submitted ? Map.of(_formState.fieldErrors) : const {},
              requiredControllers: const {},
              requiredHint: '',
              optionalHint: '',
              keyedErrors: _submitted && _formState.fieldErrors.containsKey(_formState.sourceActionIdController)
                  ? {_formState.sourceActionIdController: _formState.fieldErrors[_formState.sourceActionIdController]!}
                  : const {},
              focusKey: _submitted && _formState.fieldErrors.containsKey(_formState.sourceActionIdController)
                  ? _formState.sourceActionIdController
                  : null,
              focusController: _submitted ? _formState.fieldErrors.keys.firstOrNull : null,
              focusRequest: _focusRequest,
              onChanged: (_) {},
              child: _buildDialogContent(
                remoteError: remoteError,
                l10n: l10n,
                provider: provider,
              ),
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                Button(
                  onPressed: provider.isSavingTrigger ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.agentActionsTriggerCancel),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: provider.isSavingTrigger || !provider.isFeatureEnabled ? null : _handleSave,
                      child: provider.isSavingTrigger
                          ? const SizedBox.square(
                              dimension: 16,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : Text(l10n.agentActionsTriggerSave),
                    ),
                    if (!provider.isFeatureEnabled && !provider.isSavingTrigger) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.agentActionsDisabledMessage,
                        style: context.bodyMuted,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ],
                ),
              ],
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
    AgentActionTriggerType.actionSucceeded => l10n.agentActionsTriggerTypeActionSucceeded,
    AgentActionTriggerType.actionFailed => l10n.agentActionsTriggerTypeActionFailed,
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
