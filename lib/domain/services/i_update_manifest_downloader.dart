import 'dart:typed_data';

import 'package:result_dart/result_dart.dart';

abstract interface class IUpdateManifestDownloader {
  /// HTTPS only, bounded in memory, including redirects and error bodies.
  Future<Result<Uint8List>> download(String url);
}
