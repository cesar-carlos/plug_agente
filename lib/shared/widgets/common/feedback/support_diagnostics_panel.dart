import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/external_url_launcher.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class SupportDiagnosticsPanel extends StatelessWidget {
  const SupportDiagnosticsPanel({
    required this.sections,
    this.showSectionTitles = true,
    super.key,
  });

  final List<SupportDiagnosticsSection> sections;
  final bool showSectionTitles;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          _SupportDiagnosticsSectionView(
            section: sections[index],
            showTitle: showSectionTitles,
          ),
        ],
      ],
    );
  }
}

class SupportDiagnosticsExpander extends StatelessWidget {
  const SupportDiagnosticsExpander({
    required this.header,
    required this.sections,
    this.initiallyExpanded = false,
    super.key,
  });

  final String header;
  final List<SupportDiagnosticsSection> sections;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Expander(
      initiallyExpanded: initiallyExpanded,
      header: Text(header, style: context.bodyStrong),
      content: SupportDiagnosticsPanel(
        sections: sections,
        showSectionTitles: sections.length > 1,
      ),
    );
  }
}

class _SupportDiagnosticsSectionView extends StatelessWidget {
  const _SupportDiagnosticsSectionView({
    required this.section,
    required this.showTitle,
  });

  final SupportDiagnosticsSection section;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Text(section.title, style: context.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
        ],
        for (final field in section.fields) ...[
          const SizedBox(height: AppSpacing.xs),
          _SupportDiagnosticsFieldRow(field: field),
        ],
      ],
    );
  }
}

class _SupportDiagnosticsFieldRow extends StatelessWidget {
  const _SupportDiagnosticsFieldRow({
    required this.field,
  });

  final SupportDiagnosticsField field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayValue = _formatValue(field.value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 188,
          child: Text(
            '${field.key}:',
            style: context.captionText,
          ),
        ),
        Expanded(
          child: ExternalUrlLauncher.looksLikeHttpUrl(displayValue)
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    SelectableText(
                      displayValue,
                      style: context.captionText.copyWith(fontWeight: FontWeight.w600),
                    ),
                    HyperlinkButton(
                      onPressed: () {
                        unawaited(ExternalUrlLauncher.launch(displayValue));
                      },
                      child: Text(l10n.configAutoUpdateReleaseNotesLink),
                    ),
                  ],
                )
              : SelectableText.rich(
                  TextSpan(
                    style: context.captionText,
                    children: [
                      TextSpan(
                        text: displayValue,
                        style: context.captionText.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  String _formatValue(Object? value) {
    if (value == null) {
      return '-';
    }

    if (value is String && value.trim().isEmpty) {
      return '-';
    }

    return value.toString();
  }
}
