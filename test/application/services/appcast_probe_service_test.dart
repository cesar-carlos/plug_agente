import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';

void main() {
  group('AppcastProbeService', () {
    test('reads latest sparkle version from local appcast feed', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
          ..write('''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure sparkle:version="1.2.3+4" />
    </item>
    <item>
      <enclosure sparkle:version="1.2.2+3" />
    </item>
  </channel>
</rss>''');
        await request.response.close();
      });

      const service = AppcastProbeService();
      final result = await service.probeLatest(
        feedUrl: 'http://127.0.0.1:${server.port}/appcast.xml',
      );

      expect(result.errorMessage, isNull);
      expect(result.latestVersion, '1.2.3+4');
      expect(result.itemCount, 2);
    });

    test('returns error details on invalid feed content', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('not-found');
        await request.response.close();
      });

      const service = AppcastProbeService();
      final result = await service.probeLatest(
        feedUrl: 'http://127.0.0.1:${server.port}/appcast.xml',
      );

      expect(result.latestVersion, isNull);
      expect(result.errorMessage, contains('HTTP 404'));
    });
  });
}
