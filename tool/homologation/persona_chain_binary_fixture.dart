import 'dart:convert';
import 'package:odbc_fast/odbc_fast.dart' as odbc;

/// Closed operator fixture only. No consumer DDL, paths, SQL or byte payloads.
Future<void> provisionBinaryChainFixture(
  odbc.OdbcService service,
  String connectionId,
  String engine,
  String database,
) async {
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(database) ||
      !['postgres', 'mssql', 'sybase'].contains(engine)) {
    throw StateError('Invalid binary fixture target.');
  }
  final actual = (await service.executeQuery(
    engine == 'postgres' ? 'SELECT CURRENT_DATABASE()' : 'SELECT DB_NAME()',
    connectionId: connectionId,
  )).getOrThrow().rows.single.single.toString();
  if (actual != database) throw StateError('Binary fixture database mismatch.');
  final nativeType = switch (engine) {
    'postgres' => 'BYTEA',
    'mssql' => 'VARBINARY(MAX)',
    _ => 'LONG BINARY',
  };
  (await service.executeQuery(
    'CREATE TABLE binary_fixture (id INTEGER PRIMARY KEY, document $nativeType NULL)',
    connectionId: connectionId,
  )).getOrThrow();
  final pdf = [...ascii.encode('%PDF-1.4\n% Se7e fixture\n'), 0, 128, 255];
  final samples = <int, List<int>?>{
    1: pdf,
    2: [137, 80, 78, 71, 13, 10, 26, 10, 0, 255],
    3: [255, 216, 255, 0, 128, 255],
    4: [...ascii.encode('RIFF0000WEBP'), 0, 255],
    5: List.generate(256, (i) => i),
    6: null,
    7: [],
    8: pdf,
    9: [...pdf, ...List.generate(80 * 1024, (i) => (i * 31 + 17) % 256)],
  };
  for (final entry in samples.entries) {
    // Closed synthetic bytes only; no identifiers or values from the consumer.
    final hex = entry.value?.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final literal = hex == null
        ? 'NULL'
        : engine == 'postgres'
        ? "decode('$hex','hex')"
        : hex.isEmpty
        ? "CAST('' AS $nativeType)"
        : '0x$hex';
    (await service.executeQuery(
      'INSERT INTO binary_fixture(id, document) VALUES (${entry.key}, $literal)',
      connectionId: connectionId,
    )).getOrThrow();
  }
}
