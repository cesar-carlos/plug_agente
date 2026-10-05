import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  setUp(E2EEnv.resetForTesting);

  test('matrix DSN alias selects the SQL Server query', () async {
    await E2EEnv.loadForTesting('''
ODBC_TEST_DSN=Driver={SQL Server};Server=fixture
ODBC_TEST_DSN_SQL_SERVER=Driver={SQL Server};Server=fixture
ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER=SELECT server_fixture
ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE=SELECT anywhere_fixture
''');
    expect(E2EEnv.odbcLongQuery, 'SELECT server_fixture');
  });

  test('generic SQL Anywhere DSN keeps its bank query', () async {
    await E2EEnv.loadForTesting('''
ODBC_TEST_DSN=Driver={SQL Anywhere};ServerName=fixture
ODBC_TEST_DSN_SQL_SERVER=Driver={SQL Server};Server=other
ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER=SELECT server_fixture
ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE=SELECT anywhere_fixture
''');
    expect(E2EEnv.odbcLongQuery, 'SELECT anywhere_fixture');
  });
}
