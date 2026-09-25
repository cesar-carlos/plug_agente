import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/security/odbc_connection_fingerprint.dart';

void main() {
  test('fingerprint keeps the driver label and hides secrets', () {
    const connectionString = 'Driver=ODBC Driver 18 for SQL Server;Server=db;UID=sa;PWD=secret';
    final fingerprint = OdbcConnectionFingerprint.of(connectionString);
    expect(fingerprint.startsWith('ODBC Driver 18 for SQL Server:'), isTrue);
    expect(fingerprint.contains('secret'), isFalse);
    expect(fingerprint.contains('db'), isFalse);
    expect(OdbcConnectionFingerprint.hash(connectionString), hasLength(16));
  });
}
