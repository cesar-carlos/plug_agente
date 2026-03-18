import 'dart:io';

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

  static final RegExp _versionRegex = RegExp('sparkle:version="([^"]+)"');
  static final RegExp _itemRegex = RegExp(r'<item(\s|>)');

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
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }

      final latestVersion = _versionRegex.firstMatch(body)?.group(1);
      final itemCount = _itemRegex.allMatches(body).length;

      return AppcastProbeResult(
        requestUrl: feedUrl,
        latestVersion: latestVersion,
        itemCount: itemCount,
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
}
