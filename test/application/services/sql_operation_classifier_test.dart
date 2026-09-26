import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

void main() {
  group('SqlOperationClassifier', () {
    late SqlOperationClassifier classifier;

    setUp(() {
      classifier = SqlOperationClassifier();
    });

    test('should classify SELECT as read', () {
      final result = classifier.classify('SELECT * FROM dbo.users');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should classify UPDATE as update', () {
      final result = classifier.classify(
        'UPDATE dbo.users SET name = "John" WHERE id = 1',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should classify DELETE as delete', () {
      final result = classifier.classify('DELETE FROM dbo.users WHERE id = 1');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.delete));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should fail on multiple statements', () {
      final result = classifier.classify(
        'SELECT * FROM users; DELETE FROM users WHERE id = 1',
      );

      expect(result.isError(), isTrue);
    });

    test('should allow semicolon inside string literal', () {
      final result = classifier.classify(
        "SELECT * FROM dbo.users WHERE note = ';'",
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should classify commented INNER JOIN as read on joined tables', () {
      final result = classifier.classify('''
/* CONTA RECEBER */
SELECT cr.CodEmpresa -- chave
FROM ContaReceber cr
INNER JOIN Cliente c ON c.CodCliente = cr.CodCliente
''');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        final names = value.resources.map((resource) => resource.normalizedName).toList()..sort();
        expect(names, equals(['cliente', 'contareceber']));
      }, (_) => fail('Expected success'));
    });

    test('should extract table from a one-level derived table', () {
      final result = classifier.classify(
        'SELECT * FROM (SELECT * FROM dbo.users) q',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        expect(
          value.resources.map((resource) => resource.normalizedName),
          contains('dbo.users'),
        );
      }, (_) => fail('Expected success'));
    });

    test('should extract table to the right of CROSS APPLY', () {
      final result = classifier.classify(
        'SELECT u.id FROM dbo.users u CROSS APPLY dbo.fn_split(u.name) s',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        final names = value.resources.map((resource) => resource.normalizedName).toList()..sort();
        expect(names, containsAll(['dbo.fn_split', 'dbo.users']));
      }, (_) => fail('Expected success'));
    });

    test('should classify INSERT SELECT target as update and source as read', () {
      final result = classifier.classify(
        'INSERT INTO dbo.target (id) SELECT id FROM dbo.source',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(
          _operationByName(value.resources),
          equals({
            'dbo.target': SqlOperation.update,
            'dbo.source': SqlOperation.read,
          }),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify INSERT VALUES with only the target as update', () {
      final result = classifier.classify(
        "INSERT INTO dbo.target (name) VALUES ('x')",
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(
          _operationByName(value.resources),
          equals({'dbo.target': SqlOperation.update}),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify DELETE JOIN source as read', () {
      final result = classifier.classify(
        'DELETE t FROM dbo.target t JOIN dbo.source s ON t.id = s.id',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.delete));
        expect(
          _operationByName(value.resources),
          equals({
            'dbo.target': SqlOperation.delete,
            'dbo.source': SqlOperation.read,
          }),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify MERGE USING source as read', () {
      final result = classifier.classify(
        'MERGE INTO dbo.target t USING dbo.source s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.x = s.x',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(
          _operationByName(value.resources),
          equals({
            'dbo.target': SqlOperation.update,
            'dbo.source': SqlOperation.read,
          }),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify CREATE VIEW body tables as read', () {
      final result = classifier.classify(
        'CREATE VIEW dbo.active_users AS SELECT * FROM dbo.users',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.ddl));
        expect(
          _operationByName(value.resources),
          equals({
            'dbo.active_users': SqlOperation.ddl,
            'dbo.users': SqlOperation.read,
          }),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify ALTER VIEW body tables as read', () {
      final result = classifier.classify(
        'ALTER VIEW dbo.active_users AS SELECT * FROM dbo.users',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.ddl));
        expect(
          _operationByName(value.resources),
          equals({
            'dbo.active_users': SqlOperation.ddl,
            'dbo.users': SqlOperation.read,
          }),
        );
      }, (_) => fail('Expected success'));
    });

    test('should extract the real table from nested derived tables inside a CTE', () {
      final result = classifier.classify(_municipioLookupSql);

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        expect(
          value.resources.map((resource) => resource.normalizedName).toList(),
          equals(['municipio']),
        );
      }, (_) => fail('Expected success'));
    });

    test('should extract both UNION sources from nested derived tables inside a CTE', () {
      final result = classifier.classify(_bairroLookupSql);

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        final names = value.resources.map((resource) => resource.normalizedName).toList()..sort();
        expect(names, equals(['cliente', 'fornecedor']));
      }, (_) => fail('Expected success'));
    });

    test('should ignore FROM keywords that appear only inside a string literal', () {
      final result = classifier.classify(
        "SELECT * FROM Municipio WHERE nome = ' from Cliente '",
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(
          value.resources.map((resource) => resource.normalizedName).toList(),
          equals(['municipio']),
        );
      }, (_) => fail('Expected success'));
    });

    test('should ignore inner CTE aliases when a derived table starts with WITH', () {
      final result = classifier.classify('''
SELECT nome
FROM (
  WITH inner_cte AS (SELECT nome FROM Municipio)
  SELECT nome FROM inner_cte
) q
''');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        final names = value.resources.map((resource) => resource.normalizedName).toList()..sort();
        expect(names, equals(['municipio']));
      }, (_) => fail('Expected success'));
    });

    test('should classify derived tables at the nesting limit', () {
      final result = classifier.classify(
        _wrapDerivedTables(
          depth: SqlOperationClassifier.maxDerivedTableDepth,
          inner: 'SELECT * FROM Municipio',
        ),
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(
          value.resources.map((resource) => resource.normalizedName).toList(),
          equals(['municipio']),
        );
      }, (_) => fail('Expected success'));
    });

    test('should fail when derived-table nesting exceeds the classification limit', () {
      final result = classifier.classify(
        _wrapDerivedTables(
          depth: SqlOperationClassifier.maxDerivedTableDepth + 1,
          inner: 'SELECT * FROM Municipio',
        ),
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          final validation = failure as domain.ValidationFailure;
          expect(validation.context['reason'], equals(SqlClassificationReasons.nestingLimit));
        },
      );
    });

    test('should fail when a derived table parenthesis is unclosed', () {
      final result = classifier.classify('SELECT * FROM (SELECT * FROM Municipio');

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          final validation = failure as domain.ValidationFailure;
          expect(validation.context['reason'], equals(SqlClassificationReasons.unclosedConstruct));
        },
      );
    });
  });
}

Map<String, SqlOperation> _operationByName(List<ClassifiedSqlResource> resources) {
  return <String, SqlOperation>{
    for (final resource in resources) resource.normalizedName: resource.operation,
  };
}

String _wrapDerivedTables({required int depth, required String inner}) {
  var sql = inner;
  for (var i = 0; i < depth; i++) {
    sql = 'SELECT * FROM ($sql) q$i';
  }
  return sql;
}

const _municipioLookupSql = '''
WITH Parametros AS (
  SELECT CAST(:limit AS INTEGER) AS MaxRows,
         CAST(:searchPattern AS VARCHAR(255)) AS SearchPattern
),
Base AS (
  SELECT DISTINCT NomeMunicipio FROM (
    SELECT UPPER(REPLACE(LTRIM(RTRIM(COALESCE(NomeOriginal, ''))), CHAR(39), '')) AS NomeMunicipio
    FROM (
      SELECT b.Nome AS NomeOriginal
      FROM Municipio b
      WHERE b.Nome IS NOT NULL AND LTRIM(RTRIM(b.Nome)) <> ''
    ) Origem
  ) N
),
Filtered AS (
  SELECT b.NomeMunicipio
  FROM Base b
  CROSS JOIN Parametros p
  WHERE LEN(b.NomeMunicipio) > 3
    AND (p.SearchPattern IS NULL OR b.NomeMunicipio LIKE p.SearchPattern)
),
Numbered AS (
  SELECT f.NomeMunicipio, ROW_NUMBER() OVER (ORDER BY f.NomeMunicipio) AS Rn
  FROM Filtered f
)
SELECT n.NomeMunicipio
FROM Numbered n
CROSS JOIN Parametros p
WHERE n.Rn <= p.MaxRows
ORDER BY n.Rn
''';

const _bairroLookupSql = '''
WITH Parametros AS (
  SELECT CAST(:limit AS INTEGER) AS MaxRows,
         CAST(:searchPattern AS VARCHAR(255)) AS SearchPattern
),
Base AS (
  SELECT DISTINCT NomeBairro FROM (
    SELECT UPPER(REPLACE(LTRIM(RTRIM(COALESCE(BairroOriginal, ''))), CHAR(39), '')) AS NomeBairro
    FROM (
      SELECT cli.Bairro AS BairroOriginal
      FROM Cliente cli
      WHERE cli.Bairro IS NOT NULL AND LTRIM(RTRIM(cli.Bairro)) <> ''
      UNION ALL
      SELECT forn.Bairro AS BairroOriginal
      FROM Fornecedor forn
      WHERE forn.Bairro IS NOT NULL AND LTRIM(RTRIM(forn.Bairro)) <> ''
    ) Origem
  ) N
),
Filtered AS (
  SELECT b.NomeBairro
  FROM Base b
  CROSS JOIN Parametros p
  WHERE LEN(b.NomeBairro) > 3
    AND (p.SearchPattern IS NULL OR b.NomeBairro LIKE p.SearchPattern)
),
Numbered AS (
  SELECT f.NomeBairro, ROW_NUMBER() OVER (ORDER BY f.NomeBairro) AS Rn
  FROM Filtered f
)
SELECT n.NomeBairro
FROM Numbered n
CROSS JOIN Parametros p
WHERE n.Rn <= p.MaxRows
ORDER BY n.Rn
''';
