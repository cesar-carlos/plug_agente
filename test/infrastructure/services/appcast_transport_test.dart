import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/errors/silent_install_failure.dart';
import 'package:plug_agente/infrastructure/services/appcast_probe_service.dart';

class ProbeAdapter implements HttpClientAdapter {
  ProbeAdapter(this.responses);
  final List<ResponseBody> responses;
  int requests = 0;
  final cancelled = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    expect(options.followRedirects, isFalse);
    unawaited(
      cancelFuture?.then((_) {
        if (!cancelled.isCompleted) cancelled.complete();
      }),
    );
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  AppcastProbeService service(ProbeAdapter adapter) => AppcastProbeService(dio: Dio()..httpClientAdapter = adapter);
  const url = 'https://example.com/appcast.xml';
  const xml =
      '<rss><channel><item><enclosure version="1" sparkle:version="1.0.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" /></item></channel></rss>';
  test('accepts the exact byte limit', () async {
    final body = xml + ' ' * (1024 * 1024 - utf8.encode(xml).length);
    final result = await service(ProbeAdapter([ResponseBody.fromString(body, 200)])).probeLatest(feedUrl: url);
    expect(result.isSuccess(), isTrue);
  });
  test('stops reading an oversized chunked body before consuming more data', () async {
    var consumed = 0;
    Stream<Uint8List> body() async* {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        consumed++;
        yield Uint8List(128 * 1024);
      }
    }

    final adapter = ProbeAdapter([ResponseBody(body(), 200)]);
    final result = await service(adapter).probeLatest(feedUrl: url);
    expect(result.exceptionOrNull(), isA<ValidationFailure>());
    expect(consumed, lessThan(20));
  });
  test('rejects a redirect to a forbidden destination before the next request', () async {
    final adapter = ProbeAdapter([
      ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://remote.example.com/appcast.xml'],
        },
      ),
    ]);
    expect((await service(adapter).probeLatest(feedUrl: url)).exceptionOrNull(), isA<ValidationFailure>());
    expect(adapter.requests, 1);
  });
  test('limits redirects and cancels their bodies', () async {
    final adapter = ProbeAdapter(
      List.generate(
        6,
        (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [url],
          },
        ),
      ),
    );
    expect((await service(adapter).probeLatest(feedUrl: url)).isError(), isTrue);
    expect(adapter.requests, 6);
  });
  test('total timeout cancels a response that never finishes', () async {
    final body = StreamController<Uint8List>();
    final adapter = ProbeAdapter([ResponseBody(body.stream, 200)]);
    final result = await service(adapter).probeLatest(feedUrl: url, timeout: const Duration(milliseconds: 30));
    expect(result.exceptionOrNull(), isA<NetworkFailure>());
    await adapter.cancelled.future.timeout(const Duration(seconds: 1));
    await body.close();
  });
  test('operator cancellation stops the response stream', () async {
    final body = StreamController<Uint8List>();
    final adapter = ProbeAdapter([ResponseBody(body.stream, 200)]);
    var cancel = false;
    final result = service(adapter).probeLatest(feedUrl: url, cancelRequested: () => cancel);
    cancel = true;
    expect((await result).exceptionOrNull(), isA<SilentInstallCancellationFailure>());
    await adapter.cancelled.future.timeout(const Duration(seconds: 1));
    await body.close();
  });
  test('invalid XML has a typed cause and safe message', () async {
    final result = await service(
      ProbeAdapter([ResponseBody.fromString('<private secret', 200)]),
    ).probeLatest(feedUrl: url);
    final failure = result.exceptionOrNull()! as ValidationFailure;
    expect(failure.cause, isNotNull);
    expect(failure.message, isNot(contains('private secret')));
  });
}
