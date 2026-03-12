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
      await tempDir.delete(recursive: true);
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
