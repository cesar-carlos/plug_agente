import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/shared/widgets/common/feedback/support_diagnostics_panel.dart';

class UpdateCheckInlineNoticeBar extends StatelessWidget {
  const UpdateCheckInlineNoticeBar({
    required this.notice,
    super.key,
  });

  final UpdateCheckInlineNotice notice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hint = notice.hint?.trim();

    return InfoBar(
      key: const ValueKey('updates_check_inline_notice'),
      title: Text(notice.message),
      severity: notice.severity,
      isLong: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint != null && hint.isNotEmpty) ...[
            Text(hint, style: context.captionText),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (notice.diagnosticSections.isNotEmpty)
            SupportDiagnosticsExpander(
              header: l10n.configUpdateTechnicalTitle,
              sections: notice.diagnosticSections,
            ),
        ],
      ),
    );
  }
}
