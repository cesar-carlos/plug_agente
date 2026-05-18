class SupportDiagnosticsField {
  const SupportDiagnosticsField({
    required this.key,
    this.value,
  });

  final String key;
  final Object? value;
}

class SupportDiagnosticsSection {
  const SupportDiagnosticsSection({
    required this.title,
    required this.fields,
  });

  final String title;
  final List<SupportDiagnosticsField> fields;
}
