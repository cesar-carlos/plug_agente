/// Filters LCOV trace content to blocks whose `SF:` path matches a prefix.
///
/// Used by `filter_lcov_info.dart` and tests. Prefixes use `/`; Windows `\` in
/// paths is normalized before comparison.
String filterLcovByPathPrefixes(String content, List<String> prefixes) {
  final normalizedPrefixes = prefixes
      .map((String p) => p.replaceAll(r'\', '/').trim())
      .where((String p) => p.isNotEmpty)
      .toList();
  if (normalizedPrefixes.isEmpty) {
    return content;
  }

  final lines = content.split(RegExp(r'\r?\n'));
  final out = <String>[];
  var buf = <String>[];
  String? currentSf;

  void flushBlock() {
    if (buf.isEmpty) {
      return;
    }
    if (currentSf != null) {
      final path = currentSf!.replaceAll(r'\', '/');
      final keep = normalizedPrefixes.any(path.startsWith);
      if (keep) {
        out.addAll(buf);
      }
    }
    buf = <String>[];
    currentSf = null;
  }

  for (final line in lines) {
    if (line == 'end_of_record') {
      buf.add(line);
      flushBlock();
      continue;
    }
    if (line.startsWith('SF:')) {
      currentSf = line.substring(3).trim();
    }
    buf.add(line);
  }
  flushBlock();

  if (out.isEmpty) {
    return '';
  }
  return '${out.join('\n')}\n';
}
