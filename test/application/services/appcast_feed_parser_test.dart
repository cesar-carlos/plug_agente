import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_feed_parser.dart';

void main() {
  const sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
 <channel>
  <item>
   <enclosure url="https://github.com/org/repo/releases/download/v2/Setup-2.exe" sparkle:version="2.0.0+5" sparkle:os="windows" length="100" type="application/octet-stream" />
  </item>
  <item>
   <enclosure url="https://github.com/org/repo/releases/download/v1/Setup-1.exe" sparkle:version="1.0.0" sparkle:os="windows" length="200" type="application/octet-stream" />
  </item>
 </channel>
</rss>
''';

  test('parseLatestWindowsItem returns first Windows enclosure', () {
    const parser = AppcastFeedParser();
    final item = parser.parseLatestWindowsItem(sample);
    expect(item, isNotNull);
    expect(item!.versionString, '2.0.0+5');
    expect(item.downloadUrl, contains('Setup-2.exe'));
    expect(item.expectedLength, 100);
  });

  test('skips non-windows sparkle:os', () {
    const xml = '''
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<item>
<enclosure url="https://x/a" sparkle:version="9" sparkle:os="macos" length="1" type="application/octet-stream" />
</item>
<item>
<enclosure url="https://github.com/x/y.exe" sparkle:version="1.0.0" sparkle:os="windows" length="3" type="application/octet-stream" />
</item>
</channel>
</rss>
''';
    const parser = AppcastFeedParser();
    final item = parser.parseLatestWindowsItem(xml);
    expect(item?.versionString, '1.0.0');
  });
}
