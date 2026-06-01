import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';

class UpdateCheckInlineNotice {
  const UpdateCheckInlineNotice({
    required this.message,
    required this.severity,
    this.hint,
    this.diagnosticSections = const <SupportDiagnosticsSection>[],
  });

  final String message;
  final String? hint;
  final InfoBarSeverity severity;
  final List<SupportDiagnosticsSection> diagnosticSections;
}
