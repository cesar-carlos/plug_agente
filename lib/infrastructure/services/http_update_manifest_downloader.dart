import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:plug_agente/domain/errors/failures.dart' show NetworkFailure;
import 'package:plug_agente/domain/services/i_update_manifest_downloader.dart';
import 'package:result_dart/result_dart.dart';

class HttpUpdateManifestDownloader implements IUpdateManifestDownloader {
  HttpUpdateManifestDownloader({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;
  static const int maxBytes = 128 * 1024;

  @override
  Future<Result<Uint8List>> download(String url) async {
    final cancellation = CancelToken();
    try {
      return Success(await _download(url, cancellation).timeout(const Duration(seconds: 30)));
    } on Object {
      cancellation.cancel();
      // Remote responses and redirect URLs never enter user diagnostics.
      return Failure(
        NetworkFailure.withContext(
          message: 'Não foi possível obter o manifesto da atualização.',
          context: const {'reason': 'manifest_download_failed'},
        ),
      );
    }
  }

  Future<Uint8List> _download(String url, CancelToken cancellation) async {
    var uri = Uri.parse(url);
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
        throw const FormatException('Manifest transport rejected');
      }
      final response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: cancellation,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          headers: {'Accept': 'application/json', 'Cache-Control': 'no-cache'},
        ),
      );
      final body = response.data;
      if (body == null) throw const FormatException('Missing manifest');
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        // Do not read unbounded redirect bodies.
        await body.stream.listen(null).cancel();
        final location = response.headers.value('location');
        if (location == null || redirects == 5) throw const FormatException('Invalid redirect');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await body.stream.listen(null).cancel();
        throw const FormatException('Unexpected manifest response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > maxBytes) throw const FormatException('Manifest too large');
        bytes.add(chunk);
      }
      if (bytes.isEmpty) throw const FormatException('Empty manifest');
      return bytes.takeBytes();
    }
    throw const FormatException('Too many redirects');
  }
}
