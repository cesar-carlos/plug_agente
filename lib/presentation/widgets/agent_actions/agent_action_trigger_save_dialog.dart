import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_coordinator.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_form_state.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/iana_timezone_id_field.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_dialog_title_bar.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
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

  late final AgentActionTriggerSaveFormState _formState;
  late final AgentActionTriggerSaveCoordinator _saveCoordinator;

  @override
  void initState() {
    super.initState();
    _formState = AgentActionTriggerSaveFormState(existing: widget.existing);
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
    _formState.dispose();
    super.dispose();
  }

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
    final ok = await _saveCoordinator.save();
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

    if (_formState.parseError != null) {
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
            : (bool? value) {
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
      AppDropdown<AgentActionTriggerType>(
        label: l10n.agentActionsTriggerFieldType,
        value: _formState.type,
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

    if (_formState.supportsMissedRunPolicy) {
      addField(
        Checkbox(
          checked: _formState.ignoreMissedRuns,
          onChanged: provider.isSavingTrigger
              ? null
              : (bool? value) {
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

    return children;
  }

  List<Widget> _buildScheduleFields({
    required AppLocalizations l10n,
    required AgentActionsProvider provider,
    required bool useTwoColumns,
  }) {
    final enabled = !provider.isSavingTrigger;
    final fields = <Widget>[];

    switch (_formState.type) {
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
              controller: _formState.startAtController,
              label: l10n.agentActionsTriggerFieldStartAt,
              enabled: enabled,
              hint: l10n.agentActionsTriggerHintDateTime,
            ),
            second: AppTextField(
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
              second: AppTextField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AppTextField(
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
              first: AppTextField(
                controller: _formState.timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(
            AppTextField(
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
              first: AppTextField(
                controller: _formState.timeOfDayController,
                label: l10n.agentActionsTriggerFieldTimeOfDay,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintTimeOfDay,
              ),
              second: AppTextField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
            ),
          )
          ..add(_buildWeekdaySelector(l10n, provider))
          ..add(
            AppTextField(
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
              first: AppTextField(
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
              first: AppTextField(
                controller: _formState.startAtController,
                label: l10n.agentActionsTriggerFieldStartAtOptional,
                enabled: enabled,
                hint: l10n.agentActionsTriggerHintDateTime,
              ),
              second: AppTextField(
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
                    : (bool? checked) {
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
