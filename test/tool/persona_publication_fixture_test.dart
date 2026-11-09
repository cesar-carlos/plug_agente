import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:test/test.dart';

import '../../tool/homologation/persona_publication_fixture.dart';

class _MockOdbcService extends Mock implements odbc.OdbcService {}

Map<String, dynamic> _supplier(String name) => {
  'table': name,
  'columns': [
    {'name': 'codfornecedor', 'type': 'integer', 'nullable': false, 'generated': false},
    {'name': 'razaosocial', 'type': 'string', 'nullable': true, 'generated': false},
  ],
  'primaryKey': ['codfornecedor'],
  'uniqueKeys': <List<String>>[],
};

void main() {
  late _MockOdbcService service;
  setUp(() => service = _MockOdbcService());

  test('accepts supplier declaration only in an isolated SQL Server fixture without database IO', () {
    final declaration = _supplier('dbo.fornecedor');
    final fixture = PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [declaration]);
    expect(fixture.tables.single, declaration);
    verifyZeroInteractions(service);
  });

  for (final engine in ['postgres', 'sybase']) {
    test('rejects SQL Server supplier name on $engine before database IO', () {
      expect(
        () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', engine, [_supplier('dbo.fornecedor')]),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
      );
      verifyZeroInteractions(service);
    });
  }

  for (final name in ['dbo.cliente_extra', 'other.fornecedor', 'dbo.fornecedor_extra', 'dbo.fornecedor;DROP TABLE x']) {
    test('rejects undeclared table $name before database IO', () {
      expect(
        () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [_supplier(name)]),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
      );
      verifyZeroInteractions(service);
    });
  }

  test('rejects operational database even for the allowed supplier name', () {
    expect(
      () => PublicationFixture(service, '', 'Campo', 'mssql', [_supplier('dbo.fornecedor')]),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid private publication fixture.')),
    );
    verifyZeroInteractions(service);
  });

  test('rejects duplicate supplier declarations before database IO', () {
    expect(
      () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [
        _supplier('dbo.fornecedor'),
        _supplier('dbo.fornecedor'),
      ]),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
    );
    verifyZeroInteractions(service);
  });
  for (final table in ['dbo.produtovendido', 'dbo.vendedor', 'dbo.municipio', 'dbo.cliente']) {
    test('accepts exact sales table $table only in disposable MSSQL without database IO', () {
      final declaration = _supplier(table);
      final fixture = PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [declaration]);
      expect(fixture.tables.single, declaration);
      verifyZeroInteractions(service);
    });
    for (final engine in ['postgres', 'sybase']) {
      test('rejects sales table $table on $engine', () {
        expect(
          () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', engine, [_supplier(table)]),
          throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
        );
        verifyZeroInteractions(service);
      });
    }
    test('rejects operational database for $table', () {
      expect(
        () => PublicationFixture(service, '', 'Campo', 'mssql', [_supplier(table)]),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid private publication fixture.')),
      );
      verifyZeroInteractions(service);
    });
    for (final invalid in [table.replaceFirst('dbo.', 'other.'), '${table}_extra', '$table;DROP TABLE x']) {
      test('rejects non-exact sales table $invalid', () {
        expect(
          () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [_supplier(invalid)]),
          throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
        );
        verifyZeroInteractions(service);
      });
    }
    test('rejects duplicate sales table $table', () {
      expect(
        () => PublicationFixture(service, '', 'se7e_persona_123456abcdef_test', 'mssql', [
          _supplier(table),
          _supplier(table),
        ]),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Invalid or duplicate fixture table.')),
      );
      verifyZeroInteractions(service);
    });
  }
}
