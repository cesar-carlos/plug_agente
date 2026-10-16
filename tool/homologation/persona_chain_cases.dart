import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/services/sql_operation_authorizer.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';

// Operator-only companion to the explicitly invoked chain fixture. This is not
// an RPC method or an endpoint. It accepts only the fixed disposable table and
// always confirms rollback before returning a passing result.
Future<bool> evaluateChainCase(
  Map<String, dynamic> job,
  OdbcSqlOperationTransactionFactory factory,
  SqlOperationAuthorizer authorizer,
  String token,
  String agentId,
) async {
  final test = job['test'] as Map<String, dynamic>;
  final fixtures = (test['input'] as Map<String, dynamic>)['fixtures'] as List<dynamic>;
  if (fixtures.length != 1 ||
      (fixtures.single as Map<String, dynamic>)['table'] != 'operation_fixture' ||
      ((fixtures.single as Map<String, dynamic>)['rows'] as List<dynamic>).isNotEmpty) {
    throw StateError('Only the fixed empty disposable table fixture is supported.');
  }
  final plan = const SqlOperationParamsReader().plan(job['command']);
  final target = (await authorizer.authorize(plan, token, agentId, plan.steps)).getOrThrow();
  final transaction = (await factory.open(target, const Duration(seconds: 30), plan: plan)).getOrThrow();
  var passed = false;
  try {
    transaction.validatePlan(plan).getOrThrow();
    // Seeding is confined to this private database and the same rollback scope.
    (await transaction.execute(
      SqlOperationStep(
        id: 'fixture_clear',
        effect: SqlOperationEffect.delete,
        sql: ['postgres'].contains(target.expectedSource?.dialect)
            ? 'DELETE FROM operation_fixture RETURNING id AS "id"'
            : 'DELETE FROM operation_fixture',
        params: {},
        outputs: {},
      ),
      {},
      const Duration(seconds: 10),
    )).getOrThrow();
    final outputs = <String, Map<String, SqlScalar>>{};
    var affected = 0;
    var conditionFailed = false;
    for (final step in plan.steps) {
      final bindings = <String, SqlScalar>{
        for (final p in step.params.entries)
          p.key: switch (p.value) {
            SqlOperationValue(:final scalar) => scalar,
            SqlOperationOutput(:final stepId, :final output) => outputs[stepId]![output]!,
          },
      };
      final result = (await transaction.execute(step, bindings, const Duration(seconds: 10))).getOrThrow();
      if (step.expectedRows != null && !step.expectedRows!.contains(result.rows.length)) {
        conditionFailed = true;
        break;
      }
      if (step.effect != SqlOperationEffect.select) {
        final count = result.directlyAffectedRows;
        if (count == null || step.affectedRows == null) throw StateError('Indeterminate direct row count.');
        if (!step.affectedRows!.contains(count)) {
          conditionFailed = true;
          break;
        }
        affected += count;
      }
      if (step.outputs.isNotEmpty) {
        if (result.rows.length != 1) throw StateError('Expected one output row.');
        outputs[step.id] = {
          for (final field in step.outputs.entries)
            field.key: SqlScalar(
              field.value,
              field.value == SqlScalarType.integer
                  ? result.rows.single[field.key].toString()
                  : result.rows.single[field.key],
            ),
        };
      }
    }
    final expected = test['expected'] as Map<String, dynamic>;
    if (expected['error'] == 'ROW_CONDITION_FAILED') {
      passed = conditionFailed;
    } else if (!conditionFailed && expected['affectedRows'] == affected && affected <= plan.maxAffectedRows) {
      final tables = expected['tables'] as List<dynamic>;
      if (tables.length != 1 ||
          (tables.single as Map<String, dynamic>)['table'] != 'operation_fixture' ||
          ((tables.single as Map<String, dynamic>)['rows'] as List<dynamic>).isNotEmpty) {
        throw StateError('Only an empty final disposable table is supported.');
      }
      final read = (await transaction.execute(
        const SqlOperationStep(
          id: 'fixture_compare',
          effect: SqlOperationEffect.select,
          sql: 'SELECT COUNT(*) AS "row_count" FROM operation_fixture',
          params: {},
          outputs: {},
        ),
        {},
        const Duration(seconds: 10),
      )).getOrThrow();
      passed = read.rows.length == 1 && read.rows.single.values.single.toString() == '0';
    }
  } finally {
    try {
      (await transaction.rollback(const Duration(seconds: 15))).getOrThrow();
    } finally {
      (await transaction.close()).getOrThrow();
    }
  }
  return passed;
}
