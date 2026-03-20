class QueryNormalizer {
  static final RegExp _whitespaceCollapse = RegExp(r'\s+');

  bool isValidQuery(String query) {
    if (query.isEmpty) return false;

    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.startsWith('drop ')) return false;
    if (normalizedQuery.startsWith('truncate ')) return false;
    if (normalizedQuery.startsWith('alter ')) return false;
    if (normalizedQuery.startsWith('create ')) return false;
    if (normalizedQuery.startsWith('delete ') && !normalizedQuery.contains('where')) {
      return false;
    }

    return true;
  }

  String sanitizeQuery(String query) {
    if (query.isEmpty) return '';

    return query.replaceAllMapped(_whitespaceCollapse, (match) => ' ').trim();
  }
}
