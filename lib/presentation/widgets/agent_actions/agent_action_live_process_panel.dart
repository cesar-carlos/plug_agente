import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_action_live_processes.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Samples only while the details surface is visible, never on every frame.
class AgentActionLiveProcessPanel extends StatefulWidget {
  const AgentActionLiveProcessPanel({required this.processes, required this.actionId, super.key});
  final AgentActionLiveProcesses processes;
  final String actionId;
  @override
  State<AgentActionLiveProcessPanel> createState() => _AgentActionLiveProcessPanelState();
}

class _AgentActionLiveProcessPanelState extends State<AgentActionLiveProcessPanel> {
  final _watch = Stopwatch()..start();
  final Map<String, ({int wall, int cpu})> _previous = {};
  final Map<String, String> _errors = {};
  final Map<String, double> _percent = {};
  Timer? _timer;
  List<AgentActionLiveProcess> _processes = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _previous.clear();
    _percent.clear();
    if (TickerMode.valuesOf(context).enabled) {
      _sample();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(_sample));
    }
  }

  @override
  void didUpdateWidget(AgentActionLiveProcessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionId != widget.actionId || oldWidget.processes != widget.processes) {
      _previous.clear();
      _percent.clear();
      _errors.clear();
      _sample();
    }
  }

  void _sample() {
    _processes = widget.processes.forAction(widget.actionId);
    final ids = _processes.map((process) => process.executionId).toSet();
    _previous.removeWhere((id, _) => !ids.contains(id));
    _errors.removeWhere((id, _) => !ids.contains(id));
    _percent.removeWhere((id, _) => !ids.contains(id));
    for (final process in _processes) {
      final id = process.executionId;
      process.readCpu().fold(
        (duration) {
          final current = (wall: _watch.elapsedMicroseconds, cpu: duration.inMicroseconds);
          final old = _previous[id];
          if (old != null && current.wall > old.wall && current.cpu >= old.cpu) {
            _percent[id] = ((current.cpu - old.cpu) / (current.wall - old.wall) * 100 / Platform.numberOfProcessors)
                .clamp(0, 100);
          }
          _previous[id] = current;
          _errors.remove(id);
        },
        (failure) {
          final message = failure is ActionFailure ? failure.message : '$failure';
          if (_errors[id] != message && failure is ActionFailure) failure.log();
          _errors[id] = message;
          _previous.remove(id);
          _percent.remove(id);
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final process in _processes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              'PID ${process.pid} · ${process.executable}\n'
              '${l10n.agentActionsLiveCpu}: ${_errors.containsKey(process.executionId)
                  ? l10n.agentActionsCpuUnavailable
                  : _percent[process.executionId] == null
                  ? '—'
                  : '${_percent[process.executionId]!.toStringAsFixed(1)}%'}',
            ),
          ),
      ],
    );
  }
}
