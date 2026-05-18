import 'dart:convert';

import 'package:plug_agente/core/support/support_diagnostics_section.dart';

class SupportDiagnosticsJsonFormatter {
  const SupportDiagnosticsJsonFormatter();

  Map<String, Object?> flattenSections(
    List<SupportDiagnosticsSection> sections, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final payload = <String, Object?>{
      ...metadata,
    };

    for (final section in sections) {
      for (final field in section.fields) {
        payload[field.key] = field.value;
      }
    }

    return payload;
  }

  String buildPrettyJson(
    List<SupportDiagnosticsSection> sections, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      flattenSections(
        sections,
        metadata: metadata,
      ),
    );
  }
}
