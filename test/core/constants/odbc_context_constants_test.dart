import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';

void main() {
  group('OdbcContextConstants', () {
    test('stageBudgetExhaustedReason builds stable wire string', () {
      expect(OdbcContextConstants.stageBudgetExhaustedReason('query'), 'query_budget_exhausted');
    });

    test('stageRetryFailedReason builds stable wire string', () {
      expect(OdbcContextConstants.stageRetryFailedReason('batch'), 'batch_retry_failed');
    });
  });
}
