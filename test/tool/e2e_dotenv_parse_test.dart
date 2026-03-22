import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_dotenv_parse.dart';

void main() {
  group('parseDotEnvContent', () {
    test('should split on first equals and trim', () {
      final m = parseDotEnvContent('  A=b=c  \n');
      expect(m['A'], 'b=c');
    });

    test('should ignore comments and empty lines', () {
      final m = parseDotEnvContent('''
# c
K=v

''');
      expect(m['K'], 'v');
      expect(m.containsKey('# c'), isFalse);
    });

    test('should strip double quotes', () {
      final m = parseDotEnvContent('X="y"');
      expect(m['X'], 'y');
    });

    test('should strip single quotes', () {
      final m = parseDotEnvContent("Z='w'");
      expect(m['Z'], 'w');
    });

    test('should strip inline notes from unquoted values', () {
      final m = parseDotEnvContent(
        'ODBC_E2E_BENCHMARK_RECORD=true — append JSONL locally\n',
      );
      expect(m['ODBC_E2E_BENCHMARK_RECORD'], 'true');
    });

    test('should preserve semicolon-separated DSN values', () {
      final m = parseDotEnvContent(
        'ODBC_TEST_DSN=DRIVER={SQL Anywhere 16};UID=dba;PWD=sql\n',
      );
      expect(
        m['ODBC_TEST_DSN'],
        'DRIVER={SQL Anywhere 16};UID=dba;PWD=sql',
      );
    });
  });
}
