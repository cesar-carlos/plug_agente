import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';

void main() {
  group('RpcSqlBudgetConstants', () {
    test('reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        RpcSqlBudgetConstants.authorizationBudgetExhaustedReason,
        RpcSqlBudgetConstants.authorizationTimeoutReason,
        RpcSqlBudgetConstants.queryBudgetExhaustedReason,
        RpcSqlBudgetConstants.queryTimeoutReason,
        RpcSqlBudgetConstants.batchBudgetExhaustedReason,
        RpcSqlBudgetConstants.bulkInsertBudgetExhaustedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
