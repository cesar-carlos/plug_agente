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
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:plug="https://plug.se7esistemas.com/appcast">
  <channel>
    <item>
      <enclosure
        url="https://example.com/downloads/PlugAgente-Setup-1.2.3.exe"
        sparkle:version="1.2.3+4"
        sparkle:os="windows"
        length="12345"
        plug:sha256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        plug:channel="stable"
        plug:rolloutPercentage="25" />
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
      expect(result.assetUrl, 'https://example.com/downloads/PlugAgente-Setup-1.2.3.exe');
      expect(result.assetSize, 12345);
      expect(result.assetName, 'PlugAgente-Setup-1.2.3.exe');
      expect(result.sha256, '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
      expect(result.os, 'windows');
      expect(result.channel, 'stable');
      expect(result.rolloutPercentage, 25);
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

    test('selects first explicit windows item when latest item targets another os', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8')
          ..write('''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:plug="https://plug.se7esistemas.com/appcast">
  <channel>
    <item>
      <enclosure
        url="https://example.com/downloads/PlugAgente-macos.zip"
        sparkle:version="2.0.0+2"
        sparkle:os="macos"
        length="10"
        plug:sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" />
    </item>
    <item>
      <enclosure
        url="https://example.com/downloads/PlugAgente-Setup-2.0.0.exe"
        sparkle:version="2.0.0+1"
        sparkle:os="windows"
        length="20"
        plug:sha256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" />
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
      expect(result.latestVersion, '2.0.0+1');
      expect(result.assetName, 'PlugAgente-Setup-2.0.0.exe');
      expect(result.os, 'windows');
      expect(result.itemCount, 2);
    });

    test('reads single quoted uppercase appcast attributes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8')
          ..write('''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <ITEM>
      <enclosure sparkle:version='2.0.0+9' />
    </ITEM>
  </channel>
</rss>''');
        await request.response.close();
      });

      const service = AppcastProbeService();
      final result = await service.probeLatest(
        feedUrl: 'http://127.0.0.1:${server.port}/appcast.xml',
      );

      expect(result.errorMessage, isNull);
      expect(result.latestVersion, '2.0.0+9');
      expect(result.itemCount, 1);
    });

    test('returns error message when appcast has only non-windows items', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8')
          ..write('''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:plug="https://plug.se7esistemas.com/appcast">
  <channel>
    <item>
      <enclosure
        url="https://example.com/PlugAgente-2.0.0.dmg"
        length="9999"
        sparkle:version="2.0.0+1"
        sparkle:os="macos"
        plug:sha256="2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" />
    </item>
  </channel>
</rss>''');
        await request.response.close();
      });

      const service = AppcastProbeService();
      final result = await service.probeLatest(
        feedUrl: 'http://127.0.0.1:${server.port}/appcast.xml',
      );

      // Should not return a macos candidate; doing so would cause a validation
      // failure that incorrectly increments the automatic failure counter.
      expect(result.latestVersion, isNull);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('Windows'));
    });

    test('returns explicit error when latest item has no sparkle version', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8')
          ..write('''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="https://example.com/latest.exe" />
    </item>
  </channel>
</rss>''');
        await request.response.close();
      });

      const service = AppcastProbeService();
      final result = await service.probeLatest(
        feedUrl: 'http://127.0.0.1:${server.port}/appcast.xml',
      );

      expect(result.latestVersion, isNull);
      expect(result.itemCount, 1);
      expect(result.errorMessage, 'Latest appcast item is missing sparkle:version');
    });
  });
}
