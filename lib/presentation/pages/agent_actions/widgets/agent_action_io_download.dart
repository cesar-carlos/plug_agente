import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:result_dart/result_dart.dart';

typedef ActionIoDownload = Future<Result<ActionIoExportSummary>> Function(ActionIoStream stream, String path);
typedef ActionIoDestinationPicker = Future<String?> Function(BuildContext context, ActionIoStream stream);

class AgentActionIoDownload extends StatefulWidget {
  const AgentActionIoDownload({required this.onExport, required this.enabled, this.pickDestination, super.key});
  final ActionIoDownload onExport;
  final bool enabled;
  final ActionIoDestinationPicker? pickDestination;

  @override
  State<AgentActionIoDownload> createState() => _AgentActionIoDownloadState();
}

class _AgentActionIoDownloadState extends State<AgentActionIoDownload> {
  bool _busy = false;
  bool _failed = false;
  ActionIoExportSummary? _summary;

  Future<void> _download(ActionIoStream stream) async {
    if (_busy || !widget.enabled) return;
    setState(() {
      _busy = true;
      _failed = false;
      _summary = null;
    });
    try {
      final destination = await (widget.pickDestination ?? _pickDestination)(context, stream);
      if (!mounted || destination == null || !widget.enabled) return;
      final result = await widget.onExport(stream, destination);
      if (!mounted) return;
      result.fold((summary) => _summary = summary, (failure) {
        if (failure is ActionFailure) failure.log();
        _failed = true;
      });
    } on Exception catch (error) {
      ActionRuntimeFailure.withContext(
        message: 'Output export could not be completed.',
        code: 'ACTION_IO_EXPORT_UI_FAILED',
        cause: error,
      ).log();
      if (mounted) _failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final stream in ActionIoStream.values)
              Button(
                onPressed: widget.enabled && !_busy ? () => unawaited(_download(stream)) : null,
                child: Text(l10n.agentActionsIoDownloadStream(stream.name)),
              ),
          ],
        ),
        if (_busy) const ProgressRing(),
        if (_failed) Text(l10n.agentActionsIoDownloadFailed),
        if (_summary case final summary?)
          Text(
            summary.outputComplete && summary.terminal
                ? l10n.agentActionsIoDownloadComplete
                : l10n.agentActionsIoDownloadPartial,
          ),
      ],
    );
  }
}

Future<String?> _pickDestination(BuildContext context, ActionIoStream stream) async {
  final l10n = AppLocalizations.of(context)!;
  final directory = await FilePicker.getDirectoryPath(dialogTitle: l10n.agentActionsIoDownloadStream(stream.name));
  if (directory == null || !context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => _DestinationDialog(directory: directory, stream: stream),
  );
}

class _DestinationDialog extends StatefulWidget {
  const _DestinationDialog({required this.directory, required this.stream});
  final String directory;
  final ActionIoStream stream;
  @override
  State<_DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<_DestinationDialog> {
  late final _name = TextEditingController(text: '${widget.stream.name}.bin');
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    final valid =
        name.isNotEmpty &&
        name != '.' &&
        name != '..' &&
        !RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) &&
        !name.endsWith('.');
    return ContentDialog(
      title: Text(l10n.agentActionsIoDownloadStream(widget.stream.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.directory),
          Text(l10n.agentActionsIoDownloadReplaceNotice),
          TextBox(controller: _name, onChanged: (_) => setState(() {})),
        ],
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: Text(l10n.agentActionsDeleteCancel)),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, p.join(widget.directory, name)) : null,
          child: Text(l10n.agentActionsIoSaveFile),
        ),
      ],
    );
  }
}
