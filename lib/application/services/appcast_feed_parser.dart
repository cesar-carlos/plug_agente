/// Parsed Windows update entry from a Sparkle appcast (RSS) body.
class AppcastWindowsItem {
  const AppcastWindowsItem({
    required this.versionString,
    required this.downloadUrl,
    this.expectedLength,
  });

  final String versionString;
  final String downloadUrl;
  final int? expectedLength;
}

/// Extracts the newest Windows [AppcastWindowsItem] from raw appcast XML.
///
/// Assumes the feed lists the newest release first (same as this project's
/// `update-appcast` workflow).
class AppcastFeedParser {
  const AppcastFeedParser();

  static final RegExp _enclosureRe = RegExp(
    r'<enclosure\s+([^>]+)/\s*>',
    caseSensitive: false,
  );

  AppcastWindowsItem? parseLatestWindowsItem(String xml) {
    for (final m in _enclosureRe.allMatches(xml)) {
      final attrs = m.group(1)!;
      final url = _readAttr(attrs, 'url');
      final version =
          _readAttr(attrs, 'sparkle:version') ??
          _readAttr(
            attrs,
            '{http://www.andymatuschak.org/xml-namespaces/sparkle}version',
          );
      if (url == null || url.isEmpty || version == null || version.isEmpty) {
        continue;
      }
      final os =
          _readAttr(attrs, 'sparkle:os') ??
          _readAttr(
            attrs,
            '{http://www.andymatuschak.org/xml-namespaces/sparkle}os',
          );
      if (os != null && os.isNotEmpty && os != 'windows') {
        continue;
      }
      final lengthRaw =
          _readAttr(attrs, 'length') ??
          _readAttr(
            attrs,
            '{http://www.andymatuschak.org/xml-namespaces/sparkle}length',
          );
      final length = int.tryParse(lengthRaw ?? '');
      return AppcastWindowsItem(
        versionString: version,
        downloadUrl: url,
        expectedLength: length,
      );
    }
    return null;
  }

  static String? _readAttr(String attributeBlob, String name) {
    final escaped = RegExp.escape(name);
    final re = RegExp('$escaped="([^"]*)"');
    return re.firstMatch(attributeBlob)?.group(1);
  }
}
