// ignore_for_file: avoid_print

/// Script para testar conexão ODBC diretamente via CMD.
///
/// Uso:
///   dart run tool/test_db_connection.dart
///   dart run tool/test_db_connection.dart "DRIVER={SQL Anywhere 16};UID=dba;PWD=sql;DBN=VL;HOST=LOCALHOST;PORT=2650"
///
/// Se não passar connection string, usa os parâmetros padrão do SQL Anywhere.
library;

import 'package:odbc_fast/odbc_fast.dart';

const _defaultConnectionString =
    'DRIVER={SQL Anywhere 16};UID=dba;PWD=sql;DBN=VL;HOST=LOCALHOST;PORT=2650';

Future<void> main(List<String> args) async {
  final connectionString =
      args.isNotEmpty ? args[0] : _defaultConnectionString;

  print('Testando conexão ODBC...');
  print('Connection string: ${_maskPassword(connectionString)}');
  print('');

  final locator = ServiceLocator()..initialize();
  final service = locator.syncService;

  final initResult = await service.initialize();
  if (initResult.isError()) {
    print('ERRO: Falha ao inicializar ODBC');
    print('  ${initResult.exceptionOrNull()}');
    return;
  }

  final connResult = await service.connect(connectionString);
  final conn = connResult.getOrNull();
  if (conn == null) {
    print('ERRO: Falha ao conectar');
    final err = connResult.exceptionOrNull();
    print('  $err');
    return;
  }

  try {
    print('Conexão estabelecida. Executando SELECT 1...');

    final queryResult = await service.executeQuery(
      'SELECT 1 AS valor',
      connectionId: conn.id,
    );

    queryResult.fold(
      (result) {
        print('');
        print('SUCESSO! Resposta recebida.');
        print('  Linhas: ${result.rowCount}');
        print('  Colunas: ${result.columns}');
        if (result.rowCount > 0 && result.rows.isNotEmpty) {
          print('  Dados: ${result.rows.first}');
        }
      },
      (error) {
        print('');
        print('ERRO ao executar SELECT 1:');
        print('  $error');
      },
    );
  } finally {
    await service.disconnect(conn.id);
    print('');
    print('Conexão encerrada.');
  }

  locator.shutdown();
}

String _maskPassword(String connectionString) {
  return connectionString.replaceAllMapped(
    RegExp('PWD=([^;]*)', caseSensitive: false),
    (m) => 'PWD=***',
  );
}
