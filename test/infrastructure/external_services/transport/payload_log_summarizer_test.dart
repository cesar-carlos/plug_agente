import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';

void main() {
  group('PayloadLogSummarizer.summarize', () {
    test('returns small map untouched without encoding', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);
      final input = {'jsonrpc': '2.0', 'id': 1, 'method': 'rpc.discover'};

      final result = summarizer.summarize('SENT', 'rpc:request', input);

      expect(identical(result, input), isTrue);
    });

    test('returns null/scalar inputs as-is', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);

      expect(summarizer.summarize('S', 'e', null), isNull);
      expect(summarizer.summarize('S', 'e', 42), 42);
      expect(summarizer.summarize('S', 'e', true), true);
      expect(summarizer.summarize('S', 'e', 'hello'), 'hello');
    });

    test('returns full payload when within threshold', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 1024);
      final input = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 99,
        'method': 'sql.execute',
        'params': {'sql': 'SELECT 1'},
      };

      final result = summarizer.summarize('SENT', 'rpc:request', input);

      expect(result, equals(input));
    });

    test('replaces oversized map with summary that preserves rpc hints', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 64);
      final big = 'x' * 4096;
      final input = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-1',
        'method': 'sql.execute',
        'params': {'sql': big},
      };

      final result = summarizer.summarize('SENT', 'rpc:request', input);

      expect(result, isA<Map<String, Object?>>());
      final summary = result as Map<String, Object?>;
      expect(summary['_log'], 'payload_summary');
      expect(summary['truncated'], isTrue);
      expect(summary['threshold_bytes'], 64);
      expect(summary['direction'], 'SENT');
      expect(summary['event'], 'rpc:request');
      expect(summary['id'], 'req-1');
      expect(summary['method'], 'sql.execute');
      expect(summary['jsonrpc'], '2.0');
    });

    test('summarizes oversized list with list_length hint', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 32);
      final input = List<int>.generate(500, (i) => i);

      final result = summarizer.summarize('RECV', 'rpc:batch', input);

      expect(result, isA<Map<String, Object?>>());
      final summary = result as Map<String, Object?>;
      expect(summary['_log'], 'payload_summary');
      expect(summary['list_length'], 500);
    });

    test('falls through to original payload on encoding errors', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);
      const notEncodable = _Unencodable();

      final result = summarizer.summarize('S', 'e', notEncodable);

      expect(identical(result, notEncodable), isTrue);
    });
  });

  group('PayloadLogSummarizer.exceedsByteBudget', () {
    test('returns false when budget is non-positive', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);
      expect(summarizer.exceedsByteBudget({'a': 1}, 0), isFalse);
      expect(summarizer.exceedsByteBudget({'a': 1}, -1), isFalse);
    });

    test('returns false for small payload under budget', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);
      expect(summarizer.exceedsByteBudget({'a': 1}, 1024), isFalse);
    });

    test('returns true when payload exceeds budget', () {
      final summarizer = PayloadLogSummarizer(thresholdBytes: 16);
      final big = {'sql': 'x' * 4096};
      expect(summarizer.exceedsByteBudget(big, 64), isTrue);
    });
  });
}

class _Unencodable {
  const _Unencodable();
}
