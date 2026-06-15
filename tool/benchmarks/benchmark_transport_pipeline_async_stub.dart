Future<Map<String, dynamic>> runTransportPipelineBenchmarkCaseAsync({
  required Map<String, dynamic> payload,
  required String benchmarkCaseName,
  required String compressionMode,
  required bool signed,
  required int iterations,
  required int threshold,
  required int gzipIsolateThresholdBytes,
}) {
  throw UnsupportedError(
    'Async transport benchmark requires Flutter (dart:ui). '
    'Use `flutter test test/infrastructure/codecs/transport_pipeline_benchmark_test.dart --tags perf` '
    'or run with a Flutter-enabled entrypoint.',
  );
}
