class QueryNormalizer {
  static final RegExp _whitespaceCollapse = RegExp(r'\s+');

  static final RegExp _disallowedStatementStart = RegExp(
    r'^(drop|truncate|alter|create|merge|grant|revoke)\b',
  );

  bool isValidQuery(String query) {
    if (query.trim().isEmpty) {
      return false;
    }

    final collapsed = query.replaceAllMapped(_whitespaceCollapse, (match) => ' ').trim().toLowerCase();

    if (_disallowedStatementStart.hasMatch(collapsed)) {
      return false;
    }

    if (collapsed.startsWith('delete ') && !collapsed.contains(' where ')) {
      return false;
    }

    return true;
  }

  String sanitizeQuery(String query) {
    if (query.isEmpty) return '';

    return query.replaceAllMapped(_whitespaceCollapse, (match) => ' ').trim();
  }
}
