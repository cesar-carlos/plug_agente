import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/services/sql_operation_statement_guard.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import '../services/sql_operation_executor_test.dart' show envelope;

void main() {
  const reader = SqlOperationParamsReader();
  test('locally calculated content hash ignores credential aliases and key order only', () {
    final raw = envelope();
    final a = reader.plan(raw);
    final reordered = Map<String, dynamic>.fromEntries(raw.entries.toList().reversed)..['client_token'] = 'token';
    expect(reader.plan(reordered).contentHash, a.contentHash);
    reordered['maxAffectedRows'] = 3;
    expect(reader.plan(reordered).contentHash, isNot(a.contentHash));
  });
  test('native source identity participates in local content hash; reference does not open a connection', () {
    final raw = envelope();
    raw['expectedSource'] = {'version': 1, 'dialect': 'postgres', 'identityHash': 'a' * 64};
    final first = reader.plan(raw);
    expect(first.expectedSource!.identityHash, 'a' * 64);
    raw['expectedSource'] = {'version': 1, 'dialect': 'postgres', 'identityHash': 'b' * 64};
    expect(reader.plan(raw).contentHash, isNot(first.contentHash));
    expect(reader.reference(raw, execution: true).expectedSource!.identityHash, 'b' * 64);
  });
  Map<String, dynamic> guarded() => envelope()
    ..['expectedSource'] = {'version': 1, 'dialect': 'postgres', 'identityHash': 'a' * 64}
    ..['expectedStructure'] = {
      'version': 1,
      'resources': [
        {
          'resource': {'schema': 'public', 'name': 'parent', 'type': 'table'},
          'columns': [
            {'name': 'id', 'nativeType': 'int4', 'nullable': false, 'size': 32, 'scale': 0},
          ],
        },
      ],
    };
  test('structural expectation is hashed, requires identity and is execution-only', () {
    final raw = guarded();
    final first = reader.plan(raw);
    expect(first.expectedStructure!.resources.single.resource.name, 'parent');
    final resources = (raw['expectedStructure'] as Map)['resources'] as List;
    final columns = (resources.single as Map)['columns'] as List;
    (columns.single as Map)['nullable'] = true;
    expect(reader.plan(raw).contentHash, isNot(first.contentHash));
    expect(() => reader.reference(raw), throwsA(isA<SqlOperationFailure>()));
    raw.remove('expectedSource');
    expect(() => reader.plan(raw), throwsA(isA<SqlOperationFailure>()));
  });
  test('structural and second identity queries consume the operation statement budget', () {
    final plan = reader.plan(guarded());
    expect(plan.nativeStatementCount('postgres'), 6);
    expect(plan.nativeStatementCount('mssql'), 8);
  });
  final invalid = <String, void Function(Map<String, dynamic>)>{
    'unknown field': (p) => p['approved'] = true,
    'untrusted digest': (p) => p['contentHash'] = 'd' * 64,
    'wrong version': (p) => p['contractVersion'] = 2,
    'credential conflict': (p) {
      p['auth'] = 'one';
      p['client_token'] = 'two';
    },
    'missing count': (p) => (p['steps'] as List<Map<String, dynamic>>).first.remove('affectedRows'),
    'forward scalar': (p) => (p['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'x': {'kind': 'step_output', 'stepId': 'insert_child', 'output': 'id'},
    },
    'numeric decimal': (p) => (p['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'x': {
        'kind': 'value',
        'scalar': {'type': 'decimal', 'value': 0.1},
      },
    },
    'integer overflow': (p) => (p['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'x': {
        'kind': 'value',
        'scalar': {'type': 'integer', 'value': '9223372036854775808'},
      },
    },
    'invalid clock time': (p) => (p['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'x': {
        'kind': 'value',
        'scalar': {'type': 'date', 'value': '2026-10-10T25:00:00Z'},
      },
    },
    'invalid calendar date': (p) => (p['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'x': {
        'kind': 'value',
        'scalar': {'type': 'date', 'value': '2026-02-31'},
      },
    },
    'no writes': (p) => p['steps'] = [
      {
        'id': 'read',
        'effect': 'select',
        'sql': 'SELECT id FROM parent',
        'params': <String, dynamic>{},
        'outputs': <String, dynamic>{},
      },
    ],
    'too many steps': (p) => p['steps'] = List.filled(33, (p['steps'] as List).first),
  };
  for (final entry in invalid.entries) {
    test('contract refuses ${entry.key}', () {
      final raw = envelope();
      entry.value(raw);
      expect(() => reader.plan(raw), throwsA(isA<SqlOperationFailure>()));
    });
  }
  SqlOperationStep step(String sql, SqlOperationEffect effect, {bool output = false}) => SqlOperationStep(
    id: 'step',
    effect: effect,
    sql: sql,
    params: const {},
    outputs: output ? {'id': SqlScalarType.integer} : const {},
    affectedRows: effect == SqlOperationEffect.select ? null : const SqlRowBounds(0, 1),
  );
  const guard = SqlOperationStatementGuard();
  for (final sql in [
    'SELECT id FROM parent',
    'SELECT COUNT(id) FROM parent WHERE id = :id',
    "SELECT COALESCE(name, 'DELETE;') FROM parent",
  ]) {
    test('safe read subset accepts $sql', () => guard.validate(step(sql, SqlOperationEffect.select)));
  }
  for (final sql in [
    'INSERT INTO parent(name) VALUES (:name) RETURNING id',
    'INSERT INTO "public"."parent" (name) VALUES (:name) RETURNING id',
    'INSERT INTO [dbo].[parent] (name) VALUES (:name)',
    'UPDATE [dbo].[parent] SET name=:name WHERE id=:id',
    'DELETE FROM "public"."parent" WHERE id=:id',
    'UPDATE parent SET name = :name WHERE id = :id',
    'DELETE FROM parent WHERE id = :id',
  ]) {
    final effect = SqlOperationEffect.values.byName(sql.split(' ').first.toLowerCase());
    test('safe write subset accepts $sql', () => guard.validate(step(sql, effect)));
  }
  final unsafe = <String, SqlOperationEffect>{
    'UPDATE parent SET name = (SELECT name FROM secret) WHERE id = :id': SqlOperationEffect.update,
    'DELETE FROM parent WHERE id IN (SELECT id FROM secret)': SqlOperationEffect.delete,
    'INSERT INTO parent(name) SELECT name FROM secret': SqlOperationEffect.insert,
    'UPDATE parent SET name = :name': SqlOperationEffect.update,
    'DELETE FROM parent': SqlOperationEffect.delete,
    'SELECT id INTO copy FROM parent': SqlOperationEffect.select,
    'SELECT public.abs(id) FROM parent': SqlOperationEffect.select,
    'SELECT pg_sleep(10) FROM parent': SqlOperationEffect.select,
    "SELECT nextval('s') FROM parent": SqlOperationEffect.select,
    'SELECT id FROM remote_db.public.parent': SqlOperationEffect.select,
    'SELECT id FROM parent; DELETE FROM parent': SqlOperationEffect.select,
    'SELECT id FROM parent -- comment': SqlOperationEffect.select,
    'WITH x AS (DELETE FROM parent RETURNING id) SELECT id FROM x': SqlOperationEffect.select,
    'EXEC procedure_name': SqlOperationEffect.select,
    'INSERT INTO parent(name) OUTPUT inserted.id INTO other VALUES (:name)': SqlOperationEffect.insert,
    'SELECT id FROM parent FOR UPDATE': SqlOperationEffect.select,
    'SELECT MAX(id) AS id FROM parent': SqlOperationEffect.select,
  };
  for (final entry in unsafe.entries) {
    test(
      'statement subset refuses ${entry.key}',
      () => expect(() => guard.validate(step(entry.key, entry.value, output: true)), throwsA(isA<Exception>())),
    );
  }
}
