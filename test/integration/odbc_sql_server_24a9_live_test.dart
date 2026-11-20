import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:uuid/uuid.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

const _sql = '''
SELECT
  cp.CodEmpresa AS codempresa,
  cp.CodFilial AS codfilial,
  cp.CodContaPagar AS codcontapagar,
  cp.NumeroTitulo AS numerotitulo,
  cp.Parcela AS parcela,
  cp.CodFornecedor AS codfornecedor,
  f.RazaoSocial AS nomefornecedor,
  cp.DataVencimento AS datavencimento,
  cp.Status AS status,
  cp.Moeda AS moeda,
  cp.SaldoPagar AS saldoemaberto
FROM dbo.contapagar AS cp
LEFT JOIN dbo.fornecedor AS f ON f.CodFornecedor = cp.CodFornecedor
WHERE cp.Status IN ('A', 'P')
  AND cp.SaldoPagar > 0
  AND cp.CodEmpresa = 1
  AND cp.CodFilial = 3
  AND (:codfornecedor IS NULL OR cp.CodFornecedor = :codfornecedor)
  AND (:nomefornecedor IS NULL OR f.RazaoSocial LIKE :nomefornecedor)
  AND (CAST(:datainicio AS date) IS NULL OR cp.DataVencimento >= CAST(:datainicio AS date))
  AND (DATEADD("day", 1, CAST(:datafim AS date)) IS NULL OR cp.DataVencimento < DATEADD("day", 1, CAST(:datafim AS date)))
ORDER BY cp.CodEmpresa, cp.CodFilial, cp.CodFornecedor, cp.DataVencimento, cp.CodContaPagar''';

void main() async {
  await E2EEnv.load();
  final dsn = E2EEnv.odbcSqlServerConnectionString;

  test(
    '24a9 pages the original multiline SELECT with nullable date markers',
    () async {
      final h = (await OdbcE2eRpcHarness.open(dsn!, OdbcE2eSqlDialect.sqlServer))!;
      addTearDown(h.shutdown);
      final service = h.locator.asyncService;
      final connection = (await service.connect(dsn)).getOrThrow();
      addTearDown(() async => (await service.disconnect(connection.id)).getOrThrow());

      Future<void> execute(String command) async {
        (await service.executeQuery(command, connectionId: connection.id)).getOrThrow();
      }

      // The incident SQL uses fixed dbo names. Keep them in a fresh catalog.
      final database = 'plug_24a9_${const Uuid().v4().replaceAll('-', '')}';
      await execute('CREATE DATABASE [$database]');
      addTearDown(() async {
        (await h.connectionPool.closeAll()).getOrThrow();
        await execute('DROP DATABASE [$database]');
      });
      final tables = '[$database].dbo';
      await execute('CREATE TABLE $tables.fornecedor (CodFornecedor int PRIMARY KEY, RazaoSocial varchar(80))');
      await execute(
        'CREATE TABLE $tables.contapagar (CodEmpresa int, CodFilial int, CodContaPagar int PRIMARY KEY, '
        'NumeroTitulo varchar(16), Parcela int, CodFornecedor int, DataVencimento date, Status char(1), '
        'Moeda char(3), SaldoPagar decimal(12,2))',
      );
      await execute("INSERT $tables.fornecedor VALUES (20353, 'Fixture')");
      final values = List.generate(31, (index) => "(1,3,${index + 1},'T',1,20353,'20261120','A','BRL',12.50)");
      await execute('INSERT $tables.contapagar VALUES ${values.join(',')}');

      final response = await h.dispatcher.dispatch(
        RpcRequest(
          jsonrpc: '2.0',
          id: '24a9-regression',
          method: 'sql.execute',
          params: {
            'database': database,
            'sql': _sql,
            'params': {'codfornecedor': 20353, 'nomefornecedor': null, 'datainicio': null, 'datafim': null},
            'options': {'page': 1, 'page_size': 30},
          },
        ),
        'e2e-agent',
      );
      expect(response.error, isNull, reason: response.error?.data.toString());
      final result = response.result! as Map<String, dynamic>;
      final rows = (result['rows'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rows.map((row) => row['codcontapagar']), orderedEquals(List.generate(30, (index) => index + 1)));
      final pagination = result['pagination'] as Map<String, dynamic>;
      expect(pagination['page'], 1);
      expect(pagination['page_size'], 30);
      expect(pagination['has_next_page'], isTrue);
    },
    skip: dsn == null,
    tags: ['live'],
  );
}
