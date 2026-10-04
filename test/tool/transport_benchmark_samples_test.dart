import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/benchmark_transport_pipeline_async_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('should retain every signed sample before calculating percentiles', () async {
    final report = await runTransportPipelineBenchmarkCaseAsync(
      payload: const {
        'rows': [
          {'id': 1, 'name': 'sample'},
        ],
      },
      benchmarkCaseName: 'retention',
      compressionMode: 'none',
      signed: true,
      iterations: 30,
      threshold: 4096,
      gzipIsolateThresholdBytes: 32768,
    );
    expect(report['send_sample_count'], 30);
    expect(report['receive_sample_count'], 30);
    expect((report['summary'] as Map<String, dynamic>)['total_messages'], 60);
    expect((report['summary'] as Map<String, dynamic>)['error_count'], 0);
  });
}
