// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/infrastructure/native/columnar_decompress_ffi.dart';
import 'package:odbc_fast/odbc_fast.dart';

Future<void> main(List<String> args) async {
  final requireColumnarCompressed = args.contains(
    '--require-columnar-compressed',
  );

  ServiceLocator? locator;
  var shouldFail = false;
  try {
    locator = ServiceLocator()
      ..initialize(
        useAsync: true,
        asyncWorkerCount: 1,
        asyncMaxPendingRequests: 4,
        asyncBackpressureMode: AsyncBackpressureMode.failFast,
      );
    final service = locator.service;
    final initResult = await service.initialize();
    if (initResult.isError()) {
      stderr.writeln(
        'Failed to initialize odbc_fast: ${initResult.exceptionOrNull()}',
      );
      exitCode = 1;
      return;
    }

    final versionResult = await service.getVersion();
    final statsResult = await service.getAsyncWorkerPoolStats();
    final supportsResultEncodingOptions = locator.nativeConnection.supportsResultEncodingOptions;
    final columnarNativeDecompressAvailable = isColumnarNativeDecompressAvailable;

    final report = <String, Object?>{
      'status': 'ok',
      'version': versionResult.getOrNull() ?? const <String, String>{},
      'async_worker_pool': statsResult.fold(
        (stats) => <String, Object?>{
          'worker_count': stats.workerCount,
          'active_requests': stats.activeRequests,
          'pending_requests': stats.pendingRequests,
          'total_routed': stats.totalRouted,
          'fallbacks_to_blocking': stats.fallbacksToBlocking,
        },
        (error) => <String, Object?>{
          'error': error.toString(),
        },
      ),
      'native_exports': <String, Object>{
        'result_encoding_options': supportsResultEncodingOptions,
        'columnar_decompress': columnarNativeDecompressAvailable,
      },
    };

    print(const JsonEncoder.withIndent('  ').convert(report));

    if (requireColumnarCompressed && (!supportsResultEncodingOptions || !columnarNativeDecompressAvailable)) {
      stderr.writeln(
        'Required columnar/compressed runtime exports are not available.',
      );
      shouldFail = true;
    }
  } on Object catch (error, stackTrace) {
    stderr.writeln('Failed to inspect odbc_fast runtime: $error');
    stderr.writeln(stackTrace);
    shouldFail = true;
  } finally {
    locator?.shutdown();
  }

  if (shouldFail) {
    exitCode = 1;
  }
}
