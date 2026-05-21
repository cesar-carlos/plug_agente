import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';

void main() {
  group('SqlPipelineContextConstants', () {
    test('sql pipeline context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        SqlPipelineContextConstants.unexpectedTaskErrorReason,
        SqlPipelineContextConstants.queueDisposedReason,
        SqlPipelineContextConstants.queueWaitTimeoutReason,
        SqlPipelineContextConstants.sqlQueueFullReason,
        SqlPipelineContextConstants.sqlValidationFailedReason,
        SqlPipelineContextConstants.invalidSqlReason,
        SqlPipelineContextConstants.resultSetCompressionFailedReason,
        SqlPipelineContextConstants.resultSetDecompressionFailedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
