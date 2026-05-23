import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/captured_output_utf8_window.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionPagedCapturedOutput extends StatefulWidget {
  const AgentActionPagedCapturedOutput({
    required this.label,
    required this.loadMoreLabel,
    required this.storageTruncated,
    required this.l10n,
    this.fullText,
    this.storedInChunks = false,
    this.onSlice,
    super.key,
  }) : assert(
         fullText != null || onSlice != null,
         'Either fullText or onSlice must be provided for output display',
       );

  final String label;
  final String loadMoreLabel;
  final String? fullText;
  final bool storedInChunks;
  final bool storageTruncated;
  final AppLocalizations l10n;
  final Future<Result<CapturedOutputUtf8Window>> Function(int, int)? onSlice;

  @override
  State<AgentActionPagedCapturedOutput> createState() => AgentActionPagedCapturedOutputState();
}

class AgentActionPagedCapturedOutputState extends State<AgentActionPagedCapturedOutput> {
  static const int _pageBytes = AgentActionRpcConstants.defaultMaxOutputBytesPerStream;

  var _visibleText = '';
  var _nextUtf8Offset = 0;
  var _hasMore = false;
  var _isLoading = false;
  var _isLoadingMore = false;
  String? _loadError;

  void _assignFromWindow(CapturedOutputUtf8Window window, {required bool append}) {
    _visibleText = append ? '$_visibleText${window.text}' : window.text;
    _nextUtf8Offset = window.nextOffset;
    _hasMore = window.responseTruncated;
    _loadError = null;
  }

  Future<void> _loadSlice({required int offsetUtf8, required bool append}) async {
    final onSlice = widget.onSlice;
    if (onSlice == null) {
      return;
    }

    setState(() {
      if (append) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
      }
      _loadError = null;
    });

    final result = await onSlice(offsetUtf8, _pageBytes);
    if (!mounted) {
      return;
    }

    result.fold(
      (CapturedOutputUtf8Window window) {
        setState(() {
          _assignFromWindow(window, append: append);
          _isLoading = false;
          _isLoadingMore = false;
        });
      },
      (Exception failure) {
        setState(() {
          _loadError = failure is domain_errors.Failure
              ? failure.message
              : widget.l10n.agentActionsDiagnosticsOutputLoadFailed;
          _isLoading = false;
          _isLoadingMore = false;
        });
      },
    );
  }

  void _loadInitialWindow() {
    final fullText = widget.fullText;
    if (fullText != null) {
      _assignFromWindow(
        sliceUtf8TextWindow(fullText, 0, _pageBytes),
        append: false,
      );
      return;
    }

    unawaited(_loadSlice(offsetUtf8: 0, append: false));
  }

  @override
  void initState() {
    super.initState();
    _loadInitialWindow();
  }

  @override
  void didUpdateWidget(covariant AgentActionPagedCapturedOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullText != widget.fullText ||
        oldWidget.storedInChunks != widget.storedInChunks ||
        oldWidget.onSlice != widget.onSlice) {
      setState(() {
        _visibleText = '';
        _nextUtf8Offset = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
        _loadError = null;
      });
      _loadInitialWindow();
    }
  }

  void _loadMore() {
    final fullText = widget.fullText;
    if (fullText != null) {
      setState(() {
        _assignFromWindow(
          sliceUtf8TextWindow(fullText, _nextUtf8Offset, _pageBytes),
          append: true,
        );
      });
      return;
    }

    unawaited(_loadSlice(offsetUtf8: _nextUtf8Offset, append: true));
  }

  @override
  Widget build(BuildContext context) {
    final suffixes = <String>[
      if (widget.storedInChunks) widget.l10n.agentActionsDiagnosticsStoredInChunks,
      if (widget.storageTruncated) widget.l10n.agentActionsDiagnosticsTruncated,
    ];
    final title = suffixes.isEmpty ? widget.label : '${widget.label} (${suffixes.join(', ')})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.captionText),
        const SizedBox(height: 2),
        if (_loadError != null)
          InfoBar(
            title: Text(widget.l10n.agentActionsDiagnosticsOutputLoadFailed),
            content: Text(_loadError!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          )
        else if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: SizedBox.square(
              dimension: 20,
              child: ProgressRing(strokeWidth: 2),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).resources.controlFillColorDefault,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              _visibleText,
              style: context.captionText,
            ),
          ),
        if (_hasMore && !_isLoading && _loadError == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: HyperlinkButton(
              onPressed: _isLoadingMore ? null : _loadMore,
              child: _isLoadingMore
                  ? const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Text(widget.loadMoreLabel),
            ),
          ),
      ],
    );
  }
}

class AgentActionDiagnosticLine extends StatelessWidget {
  const AgentActionDiagnosticLine({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final caption = context.captionText;
    return SizedBox(
      width: 240,
      child: SelectableText.rich(
        TextSpan(
          style: caption,
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgentActionOutputBlock extends StatelessWidget {
  const AgentActionOutputBlock({
    required this.label,
    required this.value,
    required this.truncated,
    required this.l10n,
    super.key,
  });

  final String label;
  final String value;
  final bool truncated;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          truncated ? '$label (${l10n.agentActionsDiagnosticsTruncated})' : label,
          style: context.captionText,
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.controlFillColorDefault,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            value,
            style: context.captionText,
          ),
        ),
      ],
    );
  }
}
