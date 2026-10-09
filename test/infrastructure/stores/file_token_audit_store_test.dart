import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';

void main() {
  group('FileTokenAuditStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('token_audit_test');
    });

    tearDown(() async {
      if (!path.isWithin(Directory.systemTemp.absolute.path, tempDir.absolute.path)) {
        throw StateError('Audit test cleanup must stay in its temporary directory');
      }
      await tempDir.delete(recursive: true);
    });

    test('preserves all concurrent JSONL records and their submission order on Windows', () async {
      final store = FileTokenAuditStore(basePath: tempDir.path);
      const count = 200;
      await Future.wait(
        List.generate(
          count,
          (i) => store.record(
            TokenAuditEvent(
              eventType: TokenAuditEventType.authorizationDenied,
              timestamp: DateTime.utc(2026),
              clientId: 'client-$i',
              metadata: {'sequence': i, 'data': 'x' * 2048},
            ),
          ),
        ),
      );
      final lines = await File(path.join(tempDir.path, 'plug_agente', 'audit', 'token_audit.jsonl')).readAsLines();
      final sequences = lines.map((line) {
        final record = jsonDecode(line) as Map<String, dynamic>;
        final metadata = record['metadata'] as Map<String, dynamic>;
        return metadata['sequence'] as int;
      }).toList();
      expect(sequences, List.generate(count, (i) => i));
    });

    test('a filesystem failure does not poison subsequent queued writes', () async {
      final obstacle = File(path.join(tempDir.path, 'obstacle'));
      await obstacle.writeAsString('test-only obstacle');
      final store = FileTokenAuditStore(basePath: obstacle.path);
      final event = TokenAuditEvent(eventType: TokenAuditEventType.create, timestamp: DateTime.utc(2026));
      await store.record(event);
      await obstacle.delete();
      await store.record(event);
      final file = File(path.join(obstacle.path, 'plug_agente', 'audit', 'token_audit.jsonl'));
      expect(await file.readAsLines(), hasLength(1));
    });

    test('an encoding error reaches its caller without poisoning the write queue', () async {
      final store = FileTokenAuditStore(basePath: tempDir.path);
      final invalid = TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026),
        metadata: {'invalid': Object()},
      );
      final first = store.record(invalid);
      final next = store.record(TokenAuditEvent(eventType: TokenAuditEventType.copy, timestamp: DateTime.utc(2026)));
      await expectLater(first, throwsA(isA<JsonUnsupportedObjectError>()));
      await next;
      final lines = await File(path.join(tempDir.path, 'plug_agente', 'audit', 'token_audit.jsonl')).readAsLines();
      expect(lines, hasLength(1));
      expect(lines.single, contains('"event_type":"copy"'));
    });

    test('should append event as JSONL line', () async {
      final store = FileTokenAuditStore(
        fileName: 'test_audit.jsonl',
        basePath: tempDir.path,
      );

      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2025, 3, 12, 10),
        clientId: 'client-1',
      );

      await store.record(event);

      final file = File(
        path.join(tempDir.path, 'plug_agente', 'audit', 'test_audit.jsonl'),
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('"event_type":"create"'));
      expect(content, contains('"client_id":"client-1"'));
      expect(content.endsWith('\n'), isTrue);
    });
  });
}
