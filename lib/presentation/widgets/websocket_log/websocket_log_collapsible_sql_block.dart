import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

const int kWebSocketLogCollapsedSqlChars = 480;

class WebSocketLogCollapsibleSqlBlock extends StatefulWidget {
  const WebSocketLogCollapsibleSqlBlock({
    required this.text,
    required this.l10n,
    this.color,
    super.key,
  });

  final String text;
  final AppLocalizations l10n;
  final Color? color;

  @override
  State<WebSocketLogCollapsibleSqlBlock> createState() => _WebSocketLogCollapsibleSqlBlockState();
}

class _WebSocketLogCollapsibleSqlBlockState extends State<WebSocketLogCollapsibleSqlBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final needTruncate = text.length > kWebSocketLogCollapsedSqlChars;
    final display = !_expanded && needTruncate ? '${text.substring(0, kWebSocketLogCollapsedSqlChars)}\n…' : text;
    final baseStyle = context.bodyMuted.copyWith(
      fontFamily: 'Consolas',
      fontSize: 11,
      color: widget.color,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                display,
                style: baseStyle,
              ),
            ),
            Tooltip(
              message: widget.l10n.wsSqlInvestigationCopyTooltip,
              child: IconButton(
                icon: const Icon(FluentIcons.copy, size: 16),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                },
              ),
            ),
          ],
        ),
        if (needTruncate)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: HyperlinkButton(
              child: Text(
                _expanded ? widget.l10n.wsSqlInvestigationShowLess : widget.l10n.wsSqlInvestigationShowMore,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
      ],
    );
  }
}
