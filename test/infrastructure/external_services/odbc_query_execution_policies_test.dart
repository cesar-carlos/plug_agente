import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_policies.dart';

void main() {
  group('OdbcQueryExecutionPolicies', () {
    test('cooperativeCancelFailure returns failure when token is cancelled', () {
      final token = CancellationToken();
      token.cancel();

      final failure = OdbcQueryExecutionPolicies.cooperativeCancelFailure(
        request: _request(),
        cancellationToken: token,
      );

      expect(failure, isNotNull);
      expect(failure!.message, 'SQL execution cancelled');
      expect(failure.context?['cooperative_cancel'], isTrue);
    });

    test('cooperativeCancelFailure returns null when token is absent or active', () {
      expect(
        OdbcQueryExecutionPolicies.cooperativeCancelFailure(
          request: _request(),
        ),
        isNull,
      );
      expect(
        OdbcQueryExecutionPolicies.cooperativeCancelFailure(
          request: _request(),
          cancellationToken: CancellationToken(),
        ),
        isNull,
      );
    });

    test('isVacuousMultiResultResponse detects empty multi-result payloads', () {
      final request = _request(expectMultipleResults: true);
      final vacuous = _response();
      final populated = _response(
        data: const [
          {'a': 1},
        ],
        resultSets: const [
          QueryResultSet(
            index: 0,
            rows: [
              {'a': 1},
            ],
            rowCount: 1,
          ),
        ],
      );

      expect(
        OdbcQueryExecutionPolicies.isVacuousMultiResultResponse(request, vacuous),
        isTrue,
      );
      expect(
        OdbcQueryExecutionPolicies.isVacuousMultiResultResponse(request, populated),
        isFalse,
      );
    });

    test('previewSqlForLog collapses whitespace and truncates long SQL', () {
      final short = OdbcQueryExecutionPolicies.previewSqlForLog('SELECT   1');
      expect(short, 'SELECT 1');

      final longSql = 'SELECT ${'x' * 200}';
      final preview = OdbcQueryExecutionPolicies.previewSqlForLog(longSql);
      expect(preview.length, lessThanOrEqualTo(OdbcQueryExecutionPolicies.multiResultSqlLogPreviewChars + 1));
      expect(preview.endsWith('…'), isTrue);
    });
  });
}

QueryRequest _request({bool expectMultipleResults = false}) {
  return QueryRequest(
    id: 'req-1',
    agentId: 'agent-1',
    query: 'SELECT 1',
    timestamp: DateTime(2026, 1, 1),
    expectMultipleResults: expectMultipleResults,
  );
}

QueryResponse _response({
  List<Map<String, dynamic>> data = const [],
  List<QueryResultSet> resultSets = const [],
  List<QueryResponseItem> items = const [],
}) {
  return QueryResponse(
    id: 'resp-1',
    requestId: 'req-1',
    agentId: 'agent-1',
    data: data,
    timestamp: DateTime(2026, 1, 1),
    resultSets: resultSets,
    items: items,
  );
}
