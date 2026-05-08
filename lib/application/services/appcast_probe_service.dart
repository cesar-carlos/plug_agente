import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

class AppcastProbeResult {
  const AppcastProbeResult({
    required this.requestUrl,
    this.latestVersion,
    this.itemCount,
    this.errorMessage,
  });

  final String requestUrl;
  final String? latestVersion;
  final int? itemCount;
  final String? errorMessage;
}

abstract interface class IAppcastProbeService {
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  });
}

class AppcastProbeService implements IAppcastProbeService {
  const AppcastProbeService();

  static const int _maxAppcastBytes = 1024 * 1024;
  static const String _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return AppcastProbeResult(
        requestUrl: feedUrl,
        errorMessage: 'Feed URL invalida',
      );
    }

    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/rss+xml,text/xml,*/*',
      );

      final response = await request.close().timeout(timeout);
      final bytes = await response.expand((chunk) => chunk).take(_maxAppcastBytes + 1).toList();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }

      if (bytes.length > _maxAppcastBytes) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'Appcast response exceeded $_maxAppcastBytes bytes',
        );
      }

      final body = utf8.decode(bytes, allowMalformed: true);
      final document = XmlDocument.parse(body);
      final channel = _firstChildElementByName(document.rootElement, 'channel');
      if (channel == null) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'Appcast missing channel element',
        );
      }

      final items = channel.childElements.where((element) => _matchesLocalName(element, 'item')).toList();
      if (items.isEmpty) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          itemCount: 0,
          errorMessage: 'Appcast missing item element',
        );
      }

      final latestItem = items.first;
      final enclosure = _firstChildElementByName(latestItem, 'enclosure');
      if (enclosure == null) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          itemCount: items.length,
          errorMessage: 'Latest appcast item is missing enclosure',
        );
      }

      final latestVersion = _sparkleVersionFromEnclosure(enclosure);
      if (latestVersion == null || latestVersion.isEmpty) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          itemCount: items.length,
          errorMessage: 'Latest appcast item is missing sparkle:version',
        );
      }

      return AppcastProbeResult(
        requestUrl: feedUrl,
        latestVersion: latestVersion,
        itemCount: items.length,
      );
    } on Exception catch (e) {
      return AppcastProbeResult(
        requestUrl: feedUrl,
        errorMessage: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static XmlElement? _firstChildElementByName(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (_matchesLocalName(child, name)) {
        return child;
      }
    }
    return null;
  }

  static bool _matchesLocalName(XmlElement element, String expected) {
    return element.name.local.toLowerCase() == expected.toLowerCase();
  }

  static String? _sparkleVersionFromEnclosure(XmlElement enclosure) {
    for (final attribute in enclosure.attributes) {
      final localName = attribute.name.local.toLowerCase();
      final prefix = attribute.name.prefix?.toLowerCase();
      final namespaceUri = attribute.name.namespaceUri;
      final qualified = attribute.name.qualified.toLowerCase();
      final isSparkleVersion =
          localName == 'version' &&
          (namespaceUri == _sparkleNamespace || prefix == 'sparkle' || qualified == 'sparkle:version');
      if (!isSparkleVersion) {
        continue;
      }
      final value = attribute.value.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
