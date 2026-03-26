/// Compares `pubspec`-style versions: `major.minor.patch` with optional `+build`.
///
/// Returns negative if [a] < [b], zero if equal, positive if [a] > [b].
int compareReleaseVersions(String a, String b) {
  final pa = _parseVersionTuple(a);
  final pb = _parseVersionTuple(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final da = i < pa.length ? pa[i] : 0;
    final db = i < pb.length ? pb[i] : 0;
    if (da != db) {
      return da.compareTo(db);
    }
  }
  return 0;
}

List<int> _parseVersionTuple(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return <int>[0];
  }
  final plusIdx = trimmed.indexOf('+');
  final main = plusIdx >= 0 ? trimmed.substring(0, plusIdx) : trimmed;
  final buildPart = plusIdx >= 0 ? trimmed.substring(plusIdx + 1) : '';
  final build = int.tryParse(buildPart) ?? 0;
  final coreParts = main
      .split('.')
      .map((String s) => int.tryParse(s.trim()) ?? 0)
      .toList();
  while (coreParts.length < 3) {
    coreParts.add(0);
  }
  return <int>[...coreParts, build];
}
