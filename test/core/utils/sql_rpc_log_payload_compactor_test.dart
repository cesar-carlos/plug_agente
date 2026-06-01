import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/sql_rpc_log_payload_compactor.dart';

void main() {
  group('SqlRpcLogPayloadCompactor', () {
    test('compacts raw rows, result set rows, and batch item rows for socket logs', () {
      final compacted =
          SqlRpcLogPayloadCompactor.compactSocketLogPayload('rpc:response', {
                'jsonrpc': '2.0',
                'id': 'req-sql',
                'result': {
                  'execution_id': 'exec-1',
                  'row_count': 1,
                  'rows': [
                    {'raw_payload': 'raw-result-row'},
                  ],
                  'column_metadata': [
                    {'name': 'CodCliente'},
                  ],
                  'result_sets': [
                    {
                      'index': 0,
                      'rows': [
                        {'raw_payload': 'raw-result-set-row'},
                      ],
                      'column_metadata': [
                        {'name': 'CodCliente'},
                      ],
                    },
                  ],
                  'items': [
                    {
                      'index': 0,
                      'ok': true,
                      'rows': [
                        {'raw_payload': 'raw-item-row'},
                      ],
                      'row_count': 1,
                      'column_metadata': [
                        {'name': 'CodCliente'},
                      ],
                    },
                  ],
                },
              })
              as Map<String, dynamic>;

      expect(compacted.toString(), isNot(contains('raw-result-row')));
      expect(compacted.toString(), isNot(contains('raw-result-set-row')));
      expect(compacted.toString(), isNot(contains('raw-item-row')));

      final result = compacted['result'] as Map<String, dynamic>;
      expect(result['rows'], SqlRpcLogPayloadCompactor.socketRowsMarker);
      expect(result['row_count'], 1);
      expect(result['column_metadata_count'], 1);
      expect(result['result_set_count'], 1);
      expect(result['total_result_set_rows'], 1);
      expect(((result['result_sets'] as List).single as Map)['rows'], SqlRpcLogPayloadCompactor.socketRowsMarker);
      expect(result['item_count'], 1);
      expect(result['total_item_rows'], 1);
      expect(((result['items'] as List).single as Map)['rows'], SqlRpcLogPayloadCompactor.socketRowsMarker);
    });

    test('uses dashboard marker while preserving existing compact metadata', () {
      final snapshot = SqlRpcLogPayloadCompactor.dashboardDataSnapshot('rpc:response', {
        'id': 'req-sql',
        'result': {
          'execution_id': 'exec-1',
          'row_count': 1,
          'rows': SqlRpcLogPayloadCompactor.socketRowsMarker,
          'column_metadata_count': 3,
          'items': [
            {
              'index': 0,
              'ok': true,
              'rows': SqlRpcLogPayloadCompactor.socketRowsMarker,
              'row_count': 1,
              'column_metadata_count': 2,
            },
          ],
        },
      });

      final result = snapshot['result'] as Map<String, dynamic>;
      expect(result['rows'], SqlRpcLogPayloadCompactor.dashboardRowsMarker);
      expect(result['column_metadata_count'], 3);
      expect(((result['items'] as List).single as Map)['rows'], SqlRpcLogPayloadCompactor.dashboardRowsMarker);
      expect(((result['items'] as List).single as Map)['column_metadata_count'], 2);
    });
  });
}
