import 'package:plug_agente/core/support/support_diagnostics_section.dart';

class SupportDiagnosticsTextFormatter {
  const SupportDiagnosticsTextFormatter();

  String formatSections(List<SupportDiagnosticsSection> sections) {
    return sections.map(_formatSection).join('\n\n');
  }

  String _formatSection(SupportDiagnosticsSection section) {
    final lines = <String>[section.title];
    lines.addAll(
      section.fields.map(
        (field) => '${field.key}: ${_formatValue(field.value)}',
      ),
    );
    return lines.join('\n');
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
