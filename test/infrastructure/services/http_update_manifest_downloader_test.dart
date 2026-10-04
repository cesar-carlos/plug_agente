import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/http_update_manifest_downloader.dart';

class ManifestAdapter implements HttpClientAdapter {
  ManifestAdapter(this.responses);
  final List<ResponseBody> responses;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    expect(options.followRedirects, isFalse);
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  HttpUpdateManifestDownloader downloader(ManifestAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpUpdateManifestDownloader(dio: dio);
  }

  test('accepts an HTTPS redirect and exact bounded bytes', () async {
    final adapter = ManifestAdapter([
      ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://assets.example.com/release.json'],
        },
      ),
      ResponseBody.fromString('{"formatVersion":1}', 200),
    ]);
    final bytes = (await downloader(adapter).download('https://example.com/release.json')).getOrThrow();
    expect(String.fromCharCodes(bytes), '{"formatVersion":1}');
    expect(adapter.requested.length, 2);
  });
  test('rejects HTTP, embedded credentials and redirect downgrade before requesting', () async {
    for (final url in ['http://example.com/release.json', 'https://user:secret@example.com/release.json']) {
      final adapter = ManifestAdapter([]);
      expect((await downloader(adapter).download(url)).isError(), isTrue);
      expect(adapter.requested, isEmpty);
    }
    final adapter = ManifestAdapter([
      ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://example.com/release.json'],
        },
      ),
    ]);
    expect((await downloader(adapter).download('https://example.com/release.json')).isError(), isTrue);
    expect(adapter.requested.length, 1);
  });
  test('bounds a streamed body without relying on content length', () async {
    final adapter = ManifestAdapter([
      ResponseBody(
        Stream.fromIterable([
          Uint8List(HttpUpdateManifestDownloader.maxBytes),
          Uint8List(1),
        ]),
        200,
      ),
    ]);
    expect((await downloader(adapter).download('https://example.com/release.json')).isError(), isTrue);
  });
  test('stops redirect loops after five redirects', () async {
    final adapter = ManifestAdapter(
      List.generate(
        6,
        (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://example.com/release.json'],
          },
        ),
      ),
    );
    expect((await downloader(adapter).download('https://example.com/release.json')).isError(), isTrue);
    expect(adapter.requested.length, 6);
  });
  test('rejects partial responses, missing data and HTTP errors', () async {
    for (final response in [
      ResponseBody.fromString('data', 206),
      ResponseBody.fromString('', 200),
      ResponseBody.fromString('remote secret must not be reported', 500),
    ]) {
      expect(
        (await downloader(ManifestAdapter([response])).download('https://example.com/release.json')).isError(),
        isTrue,
      );
    }
  });
}
