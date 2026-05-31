import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  setUp(E2EEnv.resetForTesting);

  test('should default CodCliente E2E flag/query when env is empty', () async {
    await E2EEnv.loadForTesting('');

    expect(E2EEnv.odbcE2eCodClienteTests, isFalse);
    expect(
      E2EEnv.odbcE2eCodClienteQuery,
      'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente',
    );
  });

  test('should read CodCliente E2E flag/query from env', () async {
    await E2EEnv.loadForTesting('''
ODBC_E2E_CODCLIENTE_TESTS=true
ODBC_E2E_CODCLIENTE_QUERY=SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente DESC
''');

    expect(E2EEnv.odbcE2eCodClienteTests, isTrue);
    expect(
      E2EEnv.odbcE2eCodClienteQuery,
      'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente DESC',
    );
  });
}
