import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';

void main() {
  group('mergeBatchOdbcTimeout', () {
    test('should return null when stage timeout is null', () {
      expect(
        mergeBatchOdbcTimeout(stageTimeout: null, timeoutMs: 30_000),
        isNull,
      );
    });

    test('should return stage only when timeoutMs is zero', () {
      expect(
        mergeBatchOdbcTimeout(
          stageTimeout: const Duration(seconds: 20),
          timeoutMs: 0,
        ),
        const Duration(seconds: 20),
      );
    });

    test('should use the smaller of stage and client cap', () {
      expect(
        mergeBatchOdbcTimeout(
          stageTimeout: const Duration(seconds: 40),
          timeoutMs: 5000,
        ),
        const Duration(seconds: 5),
      );
      expect(
        mergeBatchOdbcTimeout(
          stageTimeout: const Duration(seconds: 5),
          timeoutMs: 30_000,
        ),
        const Duration(seconds: 5),
      );
    });
  });
}
